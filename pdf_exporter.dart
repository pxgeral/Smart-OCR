import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/ocr_result.dart';

/// PDF searchable: gambar halaman + teks OCR transparan di posisi aslinya.
abstract final class PdfExporter {
  static Future<Uint8List> build(OcrResult ocr, List<String> imagePaths) async {
    final doc = pw.Document();
    for (var i = 0; i < ocr.pages.length && i < imagePaths.length; i++) {
      final page = ocr.pages[i];
      final image = pw.MemoryImage(await File(imagePaths[i]).readAsBytes());
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(page.width, page.height),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(children: [
          pw.Image(image,
              width: page.width, height: page.height, fit: pw.BoxFit.fill),
          for (final b in page.boxes)
            pw.Positioned(
              left: b.left,
              top: b.top,
              child: pw.Opacity(
                opacity: 0,
                child: pw.Text(
                  _latin(b.text),
                  softWrap: false,
                  style: pw.TextStyle(fontSize: math.max(1, b.height * 0.8)),
                ),
              ),
            ),
        ]),
      ));
    }
    return doc.save();
  }

  /// Font bawaan PDF hanya Latin-1: ganti tanda baca umum, sisanya '?'.
  static String _latin(String s) {
    const map = {
      '‘': "'",
      '’': "'",
      '“': '"',
      '”': '"',
      '–': '-',
      '—': '-',
      '…': '...',
      '•': '*',
    };
    final sb = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      sb.write(map[ch] ?? (r < 256 ? ch : '?'));
    }
    return sb.toString();
  }
}
