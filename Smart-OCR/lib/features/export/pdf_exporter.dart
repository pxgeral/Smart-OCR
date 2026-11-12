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
      final format = page.width >= page.height
          ? PdfPageFormat.a4.landscape
          : PdfPageFormat.a4;
      final scale = math.min(format.width / page.width,
              format.height / page.height)
          .toDouble();
      final imageWidth = page.width * scale;
      final imageHeight = page.height * scale;
      final offsetX = (format.width - imageWidth) / 2;
      final offsetY = (format.height - imageHeight) / 2;
      doc.addPage(pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(children: [
          pw.Positioned(
            left: offsetX,
            top: offsetY,
            child: pw.Image(
              image,
              width: imageWidth,
              height: imageHeight,
              fit: pw.BoxFit.fill,
            ),
          ),
          for (final b in page.boxes)
            pw.Positioned(
              left: offsetX + b.left * scale,
              top: offsetY + b.top * scale,
              child: pw.Opacity(
                opacity: 0,
                child: pw.Text(
                  _latin(b.text),
                  softWrap: false,
                  style: pw.TextStyle(
                    fontSize: math.max(1.0, b.height * scale * 0.8),
                  ),
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
