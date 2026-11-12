import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../converter/page_analyzer.dart';

/// Pembacaan tabel dengan Gemini (online, opsional).
///
/// Struktur tabel (baris/kolom/sel gabungan) tetap dari deteksi garis di
/// perangkat; Gemini hanya diminta membaca isi tiap sel berdasarkan kotak
/// koordinatnya. Hasilnya menjadi kandidat berbobot tinggi yang tetap
/// dicek pola kolom & rumus oleh CellVerifier.
class GeminiReader {
  GeminiReader({required this.apiKey, this.model = defaultModel});

  static const defaultModel = 'gemini-flash-latest';
  static const _host = 'generativelanguage.googleapis.com';

  final String apiKey;
  final String model;

  /// Mengembalikan teks per indeks sel (sesuai urutan [table.cells]).
  Future<Map<int, String>> readTable(String imagePath, TableInfo table) async {
    final crop = await _cropTable(imagePath, table);
    final cells = <Map<String, Object>>[];
    for (var i = 0; i < table.cells.length; i++) {
      final c = table.cells[i];
      if (c.checkbox != 0) continue; // kotak centang sudah dikenali
      // koordinat 0-1000 relatif potongan: [ymin, xmin, ymax, xmax]
      int nx(double x) => ((x - crop.x0) / crop.w * 1000).round().clamp(0, 1000);
      int ny(double y) => ((y - crop.y0) / crop.h * 1000).round().clamp(0, 1000);
      cells.add({
        'id': i,
        'row': c.row + 1,
        'col': c.col + 1,
        if (c.rowSpan > 1) 'rowspan': c.rowSpan,
        if (c.colSpan > 1) 'colspan': c.colSpan,
        'box': [ny(c.box[1]), nx(c.box[0]), ny(c.box[3]), nx(c.box[2])],
      });
    }
    if (cells.isEmpty) return {};
    final prompt = '''
You are an expert transcriber of scanned forms and tables, including Indonesian handwriting.
The image shows one table. Its grid was already detected; each cell is listed below with an id,
row/column (1-based, with rowspan/colspan for merged cells) and a bounding box
[ymin, xmin, ymax, xmax] normalized to 0-1000 on this image.

Transcribe the content of EVERY listed cell exactly as written:
- Keep the original language (Indonesian), spelling, capitalization and punctuation.
- Keep number formats exactly: decimal comma or point as written (e.g. "5,10", "92.6"),
  times like "09.30", dates like "04/03/2025" (slashes are separators, never the digit 1).
- Handwriting: read carefully digit by digit; use the column header and neighbouring rows
  as context, but never invent values that are not visible.
- Text that visually overflows across a cell border belongs to the cell where it starts.
- Ticked checkbox = "☑", empty checkbox = "☐". A dash or stroke used as "empty" = "-".
- Multi-line cell text: join lines with "\\n".
- Empty cell = "".
Return JSON only: {"cells":[{"id":<id>,"text":"<content>"}]} with one entry per listed id.

Cells:
${jsonEncode(cells)}
''';
    final body = {
      'contents': [
        {
          'parts': [
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(crop.jpeg)}
            },
            {'text': prompt},
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0,
        'responseMimeType': 'application/json',
      },
    };
    final text = await _post(body);
    final out = <int, String>{};
    final decoded = jsonDecode(_stripFence(text));
    final list = decoded is Map ? decoded['cells'] : decoded;
    if (list is! List) throw const FormatException('Jawaban Gemini tidak berisi daftar sel');
    for (final e in list) {
      if (e is! Map) continue;
      final id = e['id'];
      final t = e['text'];
      final idx = id is int ? id : int.tryParse('$id');
      if (idx != null && t is String) out[idx] = t;
    }
    return out;
  }

  /// Uji kunci API dengan permintaan kecil.
  Future<void> ping() async {
    await _post({
      'contents': [
        {
          'parts': [
            {'text': 'Reply with OK'}
          ]
        }
      ],
      'generationConfig': {'temperature': 0, 'maxOutputTokens': 5},
    });
  }

  Future<String> _post(Map<String, Object> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.https(_host, '/v1beta/models/$model:generateContent');
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.headers.set('x-goog-api-key', apiKey);
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(seconds: 180));
      final txt = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        String msg = txt;
        try {
          msg = (jsonDecode(txt) as Map)['error']['message'] as String;
        } catch (_) {}
        throw HttpException('Gemini ${res.statusCode}: ${msg.length > 200 ? msg.substring(0, 200) : msg}');
      }
      final json = jsonDecode(txt) as Map<String, dynamic>;
      final cands = json['candidates'] as List? ?? const [];
      if (cands.isEmpty) throw const HttpException('Gemini tidak memberi jawaban');
      final parts = (cands.first as Map)['content']?['parts'] as List? ?? const [];
      final sb = StringBuffer();
      for (final p in parts) {
        if (p is Map && p['thought'] != true && p['text'] is String) sb.write(p['text']);
      }
      return sb.toString();
    } on SocketException {
      throw const HttpException('Tidak ada koneksi internet');
    } on TimeoutException {
      throw const HttpException('Gemini terlalu lama merespons');
    } finally {
      client.close(force: true);
    }
  }

  static String _stripFence(String s) {
    var t = s.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*'), '');
      if (t.endsWith('```')) t = t.substring(0, t.length - 3);
    }
    return t.trim();
  }

  static Future<_Crop> _cropTable(String path, TableInfo t) {
    final box = [t.left, t.top, t.right, t.bottom];
    return Isolate.run(() => _cropSync(path, box));
  }
}

class _Crop {
  _Crop(this.jpeg, this.x0, this.y0, this.w, this.h);
  final List<int> jpeg;
  final double x0, y0, w, h; // area potongan pada gambar halaman (px)
}

_Crop _cropSync(String path, List<double> box) {
  final src = img.decodeImage(File(path).readAsBytesSync())!;
  final mx = (box[2] - box[0]) * 0.02, my = (box[3] - box[1]) * 0.02;
  final x0 = math.max(0, (box[0] - mx).floor());
  final y0 = math.max(0, (box[1] - my).floor());
  final x1 = math.min(src.width, (box[2] + mx).ceil());
  final y1 = math.min(src.height, (box[3] + my).ceil());
  var crop = img.copyCrop(src, x: x0, y: y0, width: x1 - x0, height: y1 - y0);
  final side = math.max(crop.width, crop.height);
  if (side > 3000) {
    final s = 3000 / side;
    crop = img.copyResize(crop,
        width: (crop.width * s).round(),
        height: (crop.height * s).round(),
        interpolation: img.Interpolation.average);
  }
  return _Crop(img.encodeJpg(crop, quality: 90), x0.toDouble(), y0.toDouble(),
      (x1 - x0).toDouble(), (y1 - y0).toDouble());
}
