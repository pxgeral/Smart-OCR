import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'spm_unigram.dart';

/// Tokenizer model Marian/OPUS-MT: SentencePiece sumber + kosakata gabungan
/// (vocab.json). Menyamai MarianTokenizer milik Hugging Face.
class MarianTokenizer {
  MarianTokenizer(this._spm, Map<String, int> vocab)
      : _vocab = vocab,
        _idToPiece = _invert(vocab),
        eosId = vocab['</s>'] ?? 0,
        unkId = vocab['<unk>'] ?? 1,
        padId = vocab['<pad>'] ?? vocab.length - 1;

  factory MarianTokenizer.fromDir(String dir) {
    final vocab = (jsonDecode(File('$dir/vocab.json').readAsStringSync())
            as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as num).toInt()));
    final Uint8List spm = File('$dir/source.spm').readAsBytesSync();
    return MarianTokenizer(SpmUnigram.parse(spm), vocab);
  }

  final SpmUnigram _spm;
  final Map<String, int> _vocab;
  final List<String?> _idToPiece;
  final int eosId, unkId, padId;

  /// Jumlah baris logit yang dihasilkan model (id terbesar + 1).
  int get vocabSize => _idToPiece.length;

  static List<String?> _invert(Map<String, int> vocab) {
    var max = 0;
    for (final id in vocab.values) {
      if (id > max) max = id;
    }
    final list = List<String?>.filled(max + 1, null);
    vocab.forEach((piece, id) => list[id] = piece);
    return list;
  }

  /// Normalisasi ringan setara nmt_nfkc untuk teks dokumen: spasi ganda
  /// diringkas, huruf lebar penuh, ligatur, dan elipsis disederhanakan.
  static String normalize(String s) {
    final sb = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0xFF01 && r <= 0xFF5E) {
        sb.writeCharCode(r - 0xFEE0);
      } else if (r == 0x2026) {
        sb.write('...');
      } else if (r == 0xFB01) {
        sb.write('fi');
      } else if (r == 0xFB02) {
        sb.write('fl');
      } else {
        sb.writeCharCode(r);
      }
    }
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Teks → id token, diakhiri token akhir kalimat. Kosong bila tidak ada isi.
  List<int> encode(String text) {
    final norm = normalize(text);
    if (norm.isEmpty) return const [];
    final pieces = _spm.encode('▁${norm.replaceAll(' ', '▁')}');
    return [for (final p in pieces) _vocab[p] ?? unkId, eosId];
  }

  /// Id token → teks. Token khusus dilewati.
  String decode(Iterable<int> ids) {
    final sb = StringBuffer();
    for (final id in ids) {
      if (id == eosId || id == padId || id < 0 || id >= _idToPiece.length) {
        continue;
      }
      final piece = _idToPiece[id];
      if (piece == null || piece == '<unk>') continue;
      sb.write(piece);
    }
    return sb.toString().replaceAll('▁', ' ').trim();
  }

  /// Memecah satu baris menjadi kalimat agar kualitas terjemahan terjaga.
  /// Potongan yang terlalu panjang dipecah lagi di koma/titik koma.
  static List<String> splitSentences(String line, {int maxChars = 300}) {
    final out = <String>[];
    for (final s in line.trim().split(RegExp(r'(?<=[.!?])\s+'))) {
      if (s.isEmpty) continue;
      if (s.length <= maxChars) {
        out.add(s);
        continue;
      }
      var cur = '';
      for (final part in s.split(RegExp(r'(?<=[,;:])\s+'))) {
        if (cur.isNotEmpty && cur.length + part.length + 1 > maxChars) {
          out.add(cur);
          cur = part;
        } else {
          cur = cur.isEmpty ? part : '$cur $part';
        }
      }
      if (cur.isNotEmpty) out.add(cur);
    }
    return out;
  }
}
