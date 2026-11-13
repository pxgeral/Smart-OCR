import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;
import 'package:onnxruntime/src/ort_status.dart';

import 'marian_tokenizer.dart';

/// Mesin terjemahan offline: model OPUS-MT (Marian) berformat ONNX int8,
/// penguraian kata dengan pencarian rakus (greedy). Isi folder model:
/// encoder.onnx, decoder.onnx, vocab.json, source.spm.
///
/// Bersifat sinkron dan berat; jalankan di isolate terpisah
/// (lihat offline_translator.dart).
class MarianEngine {
  MarianEngine._(this._tok, this._enc, this._dec, this._runOptions);

  static bool _envReady = false;

  final MarianTokenizer _tok;
  final OrtSession _enc;
  final OrtSession _dec;
  final OrtRunOptions _runOptions;

  MarianTokenizer get tokenizer => _tok;

  static MarianEngine open(String dir) {
    if (!_envReady) {
      OrtEnv.instance.init();
      _envReady = true;
    }
    final tok = MarianTokenizer.fromDir(dir);
    final opts = OrtSessionOptions();
    final enc = OrtSession.fromFile(File('$dir/encoder.onnx'), opts);
    final dec = OrtSession.fromFile(File('$dir/decoder.onnx'), opts);
    opts.release();
    return MarianEngine._(tok, enc, dec, OrtRunOptions());
  }

  /// Id token keluaran untuk satu kalimat (tanpa token awal/akhir).
  List<int> translateIds(List<int> src, {bool Function()? isCancelled}) {
    final n = src.length;
    final srcIds = OrtValueTensor.createTensorWithDataList(src, [1, n]);
    final mask =
        OrtValueTensor.createTensorWithDataList(List<int>.filled(n, 1), [1, n]);
    OrtValue? hidden;
    try {
      final encOut = _enc.run(
        _runOptions,
        {'input_ids': srcIds, 'attention_mask': mask},
        ['last_hidden_state'],
      );
      hidden = encOut[0]!;

      final maxNew = math.min(300, (n * 1.5).ceil() + 10);
      final out = <int>[_tok.padId]; // token awal dekoder = pad (Marian)
      for (var step = 0; step < maxNew; step++) {
        if (isCancelled?.call() ?? false) {
          throw StateError('dibatalkan');
        }
        final next = _nextToken(out, hidden, mask);
        if (next == _tok.eosId) break;
        out.add(next);
      }
      return out.sublist(1);
    } finally {
      srcIds.release();
      mask.release();
      hidden?.release();
    }
  }

  String translate(String text, {bool Function()? isCancelled}) {
    final src = _tok.encode(text);
    if (src.length <= 1) return text;
    return _tok.decode(translateIds(src, isCancelled: isCancelled));
  }

  int _nextToken(List<int> decoded, OrtValue hidden, OrtValue mask) {
    final decIds =
        OrtValueTensor.createTensorWithDataList(decoded, [1, decoded.length]);
    List<OrtValue?>? res;
    try {
      res = _dec.run(
        _runOptions,
        {
          'input_ids': decIds,
          'encoder_hidden_states': hidden,
          'encoder_attention_mask': mask,
        },
        ['logits'],
      );
      return _argmaxRow(res[0]!, decoded.length - 1, _tok.vocabSize, _tok.padId);
    } finally {
      decIds.release();
      res?.forEach((v) => v?.release());
    }
  }

  /// Token terbesar pada baris [row] keluaran logit berukuran
  /// [1, panjang, vocab]. Dibaca langsung dari memori ORT: mengubah seluruh
  /// tensor menjadi daftar Dart terlalu lambat untuk kosakata ±55 ribu.
  static int _argmaxRow(OrtValue logits, int row, int vocab, int banned) {
    final dataPtrPtr = calloc<ffi.Pointer<ffi.Void>>();
    try {
      final status = OrtEnv.instance.ortApiPtr.ref.GetTensorMutableData
              .asFunction<
                  bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
                      ffi.Pointer<ffi.Pointer<ffi.Void>>)>()(
          logits.ptr, dataPtrPtr);
      OrtStatus.checkOrtStatus(status);
      final base = dataPtrPtr.value.cast<ffi.Float>();
      final view = base.elementAt(row * vocab).asTypedList(vocab);
      var best = -1;
      var bestValue = double.negativeInfinity;
      for (var i = 0; i < vocab; i++) {
        if (i == banned) continue;
        final v = view[i];
        if (v > bestValue) {
          bestValue = v;
          best = i;
        }
      }
      return best;
    } finally {
      calloc.free(dataPtrPtr);
    }
  }

  void close() {
    _enc.release();
    _dec.release();
    _runOptions.release();
  }
}

/// Menerjemahkan satu baris/sel: dipecah per kalimat, spasi tepi dipertahankan.
String translateLine(MarianEngine engine, String line,
    {bool Function()? isCancelled}) {
  final lead = RegExp(r'^\s*').stringMatch(line) ?? '';
  final trail = RegExp(r'\s*$').stringMatch(line) ?? '';
  final parts = [
    for (final s in MarianTokenizer.splitSentences(line))
      engine.translate(s, isCancelled: isCancelled),
  ];
  if (parts.isEmpty) return line;
  return '$lead${parts.join(' ')}$trail';
}
