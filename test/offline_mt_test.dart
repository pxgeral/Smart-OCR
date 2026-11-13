import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ocr_converter/features/translate/offline/marian_engine.dart';
import 'package:smart_ocr_converter/features/translate/offline/marian_tokenizer.dart';
import 'package:smart_ocr_converter/features/translate/offline/offline_translator.dart';
import 'package:smart_ocr_converter/features/translate/offline/spm_unigram.dart';

/// Membuat berkas .spm (protobuf) buatan untuk menguji pembaca & Viterbi.
Uint8List buildSpm(List<(String, double, int)> pieces) {
  final out = BytesBuilder();
  void varint(int v) {
    while (v > 0x7f) {
      out.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.addByte(v);
  }

  for (final (piece, score, type) in pieces) {
    final inner = BytesBuilder();
    final pb = utf8.encode(piece);
    inner.addByte(0x0a); // field 1, string
    inner.addByte(pb.length);
    inner.add(pb);
    inner.addByte(0x15); // field 2, float32
    inner.add((ByteData(4)..setFloat32(0, score, Endian.little)).buffer.asUint8List());
    inner.addByte(0x18); // field 3, varint
    inner.addByte(type);
    out.addByte(0x0a); // ModelProto.pieces
    varint(inner.length);
    out.add(inner.toBytes());
  }
  // bidang lain (trainer_spec, field 2) harus dilewati dengan benar
  out.addByte(0x12);
  out.addByte(3);
  out.add([1, 2, 3]);
  return out.toBytes();
}

void main() {
  group('SpmUnigram & MarianTokenizer', () {
    final spm = SpmUnigram.parse(buildSpm([
      ('<unk>', 0, 2),
      ('</s>', 0, 3),
      ('▁', -1, 1),
      ('▁saya', -5, 1),
      ('▁sa', -6, 1),
      ('ya', -4, 1),
      ('▁makan', -20, 1),
      ('▁ma', -3, 1),
      ('kan', -3, 1),
      ('s', -8, 1),
      ('a', -8, 1),
    ]));

    test('Viterbi memilih segmentasi dengan skor total terbaik', () {
      expect(spm.encode('▁saya'), ['▁saya']); // -5 lebih baik dari -6 + -4
      expect(spm.encode('▁makan'), ['▁ma', 'kan']); // -6 lebih baik dari -20
    });

    test('token khusus tidak dicocokkan dan karakter asing dipertahankan', () {
      expect(spm.pieceCount, 9); // <unk> dan </s> tidak ikut
      expect(spm.encode('▁saya?'), ['▁saya', '?']);
    });

    test('normalisasi, encode, dan decode', () {
      expect(MarianTokenizer.normalize('  Saya   makan\n nasi… '),
          'Saya makan nasi...');
      final tok = MarianTokenizer(spm, {
        '</s>': 0,
        '<unk>': 1,
        '▁saya': 2,
        '▁ma': 3,
        'kan': 4,
        '▁': 5,
        '<pad>': 6,
      });
      expect(tok.encode('saya makan'), [2, 3, 4, 0]); // diakhiri </s>
      expect(tok.encode('   '), isEmpty);
      expect(tok.decode([2, 3, 4, 0, 6]), 'saya makan');
      expect(tok.vocabSize, 7);
    });

    test('pemecah kalimat', () {
      expect(
        MarianTokenizer.splitSentences('Halo dunia. Apa kabar? Baik!'),
        ['Halo dunia.', 'Apa kabar?', 'Baik!'],
      );
      final long = List.filled(40, 'kata, kata').join(', ');
      final parts = MarianTokenizer.splitSentences(long, maxChars: 100);
      expect(parts.every((p) => p.length <= 100), isTrue);
      expect(parts.join(' ').replaceAll(RegExp(r'\s+'), ' '),
          long.replaceAll(RegExp(r'\s+'), ' '));
    });
  });

  // Uji dengan model sungguhan: dijalankan CI (.github/workflows/uji-terjemahan-offline.yml)
  // dengan MODELS_DIR=assets/models, REF_JSON=<keluaran tool/ref_terjemah.py>,
  // dan libonnxruntime.so ada di LD_LIBRARY_PATH.
  final modelsDir = Platform.environment['MODELS_DIR'];
  final refPath = Platform.environment['REF_JSON'];
  final skip = (modelsDir == null || refPath == null)
      ? 'butuh MODELS_DIR dan REF_JSON (hanya di CI)'
      : false;

  group('mesin offline vs referensi Python (model asli)', () {
    late List<Map<String, dynamic>> refs;
    final engines = <String, MarianEngine>{};

    setUpAll(() {
      // setUpAll tetap berjalan walau tesnya dilewati, jadi jaga bila env kosong
      if (refPath == null) {
        refs = const [];
        return;
      }
      refs = (jsonDecode(File(refPath).readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
    });
    tearDownAll(() {
      for (final e in engines.values) {
        e.close();
      }
    });

    MarianEngine engine(String dir) =>
        engines.putIfAbsent(dir, () => MarianEngine.open('$modelsDir/$dir'));

    test('tokenizer: id token sama persis dengan SentencePiece Python', () {
      var bad = 0;
      for (final r in refs) {
        final ids = engine(r['dir'] as String).tokenizer.encode(r['text'] as String);
        if (ids.join(',') != (r['src_ids'] as List).join(',')) {
          bad++;
          // ignore: avoid_print
          print('TOKEN BEDA [${r['dir']}] ${r['text']}\n  dart:   $ids\n  python: ${r['src_ids']}');
        }
      }
      expect(bad, 0);
    }, skip: skip, timeout: const Timeout(Duration(minutes: 10)));

    test('terjemahan: hasil Dart cocok dengan referensi', () {
      var same = 0;
      final watch = Stopwatch();
      for (final r in refs) {
        final e = engine(r['dir'] as String);
        watch
          ..reset()
          ..start();
        final out = e.translate(r['text'] as String);
        watch.stop();
        final ok = out == r['out_text'];
        if (ok) same++;
        // ignore: avoid_print
        print('${ok ? "SAMA " : "BEDA "} [${r['dir']}] ${watch.elapsedMilliseconds} ms\n'
            '  asal:    ${r['text']}\n  dart:    $out\n  python:  ${r['out_text']}');
      }
      // ORT Python (versi lebih baru) dan ORT 1.15.1 boleh beda tipis pada kalimat panjang
      expect(same / refs.length, greaterThanOrEqualTo(0.8));
    }, skip: skip, timeout: const Timeout(Duration(minutes: 20)));

    test('isolate pekerja: hasil sama dan bisa dibatalkan', () async {
      final dir = '$modelsDir/id-en';
      final texts = refs
          .where((r) => r['dir'] == 'id-en')
          .take(3)
          .map((r) => r['text'] as String)
          .toList();
      final out = await OfflineTranslator.translateAll(dir, texts);
      final expected = refs.where((r) => r['dir'] == 'id-en').take(3).map((r) => r['out_text']).toList();
      // ignore: avoid_print
      print('isolate: $out');
      expect(out.length, 3);
      expect(out.where((t) => expected.contains(t)).length, greaterThanOrEqualTo(2));

      final cancel = OfflineCancel();
      final fut = OfflineTranslator.translateAll(dir, List.filled(50, texts.first), cancel: cancel);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      cancel.cancel();
      await expectLater(fut, throwsA(anything));
    }, skip: skip, timeout: const Timeout(Duration(minutes: 10)));
  });
}
