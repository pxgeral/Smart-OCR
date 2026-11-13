import 'dart:convert';
import 'dart:typed_data';

/// Pembaca model SentencePiece (.spm, protobuf) dan segmentasi unigram
/// (Viterbi), cukup untuk tokenisasi sumber model terjemahan OPUS-MT.
class SpmUnigram {
  SpmUnigram._(this._scores, this._maxLen, this._unkScore);

  final Map<String, double> _scores;
  final int _maxLen;
  final double _unkScore;

  int get pieceCount => _scores.length;

  /// Tipe potongan: 1 normal, 2 unknown, 3 control, 4 user-defined,
  /// 5 unused, 6 byte. Hanya tipe 1 dan 4 yang dicocokkan ke teks.
  static SpmUnigram parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var pos = 0;

    int varint() {
      var result = 0, shift = 0;
      while (true) {
        final b = bytes[pos++];
        result |= (b & 0x7f) << shift;
        if (b & 0x80 == 0) return result;
        shift += 7;
      }
    }

    void skip(int wire) {
      switch (wire) {
        case 0:
          varint();
        case 1:
          pos += 8;
        case 2:
          pos += varint();
        case 5:
          pos += 4;
        default:
          throw FormatException('Tipe protobuf tidak dikenal: $wire');
      }
    }

    final scores = <String, double>{};
    var maxLen = 1;
    var minScore = 0.0;
    while (pos < bytes.length) {
      final tag = varint();
      if (tag >> 3 != 1 || tag & 7 != 2) {
        skip(tag & 7);
        continue;
      }
      final end = pos + varint();
      String? piece;
      var score = 0.0;
      var type = 1;
      while (pos < end) {
        final t = varint();
        final field = t >> 3, wire = t & 7;
        if (field == 1 && wire == 2) {
          final len = varint();
          piece = utf8.decode(bytes.sublist(pos, pos + len));
          pos += len;
        } else if (field == 2 && wire == 5) {
          score = data.getFloat32(pos, Endian.little);
          pos += 4;
        } else if (field == 3 && wire == 0) {
          type = varint();
        } else {
          skip(wire);
        }
      }
      if (piece == null || (type != 1 && type != 4)) continue;
      scores[piece] = score;
      final len = piece.runes.length;
      if (len > maxLen) maxLen = len;
      if (score < minScore) minScore = score;
    }
    if (scores.isEmpty) {
      throw const FormatException('Model SentencePiece kosong atau rusak');
    }
    return SpmUnigram._(scores, maxLen, minScore - 10);
  }

  /// Memecah [text] (sudah dinormalisasi, spasi berupa "▁") menjadi potongan
  /// dengan skor total terbaik. Karakter yang tidak dikenal dikembalikan
  /// apa adanya (akan dipetakan ke <unk> oleh pemanggil).
  List<String> encode(String text) {
    final chars = text.runes.map(String.fromCharCode).toList();
    final n = chars.length;
    if (n == 0) return const [];
    final best = List<double>.filled(n + 1, double.negativeInfinity);
    final from = List<int>.filled(n + 1, 0);
    best[0] = 0;
    for (var i = 0; i < n; i++) {
      final base = best[i];
      if (base == double.negativeInfinity) continue;
      final sb = StringBuffer();
      var hasSingle = false;
      for (var j = i; j < n && j - i < _maxLen; j++) {
        sb.write(chars[j]);
        final s = _scores[sb.toString()];
        if (s == null) continue;
        if (j == i) hasSingle = true;
        final cand = base + s;
        if (cand > best[j + 1]) {
          best[j + 1] = cand;
          from[j + 1] = i;
        }
      }
      if (!hasSingle) {
        final cand = base + _unkScore;
        if (cand > best[i + 1]) {
          best[i + 1] = cand;
          from[i + 1] = i;
        }
      }
    }
    final out = <String>[];
    for (var k = n; k > 0; k = from[k]) {
      out.add(chars.sublist(from[k], k).join());
    }
    return out.reversed.toList();
  }
}
