import 'dart:io';
import 'dart:math' as math;

import 'package:pdfx/pdfx.dart';

import '../../core/constants.dart';
import '../../core/failure.dart';
import '../../services/file_service.dart';

/// PDF (scan, foto, atau teks) -> JPEG per halaman untuk OCR.
class PdfRasterizer {
  PdfRasterizer(this._files);
  final FileService _files;

  Future<({List<String> paths, Directory dir})> render(
    String pdfPath, {
    void Function(int done, int total)? onProgress,
    int maxSide = AppConstants.maxImageSide,
    int? maxPages,
  }) async {
    final doc = await PdfDocument.openFile(pdfPath);
    Directory? outputDir;
    try {
      final total = doc.pagesCount;
      if (total > AppConstants.maxPdfPages) {
        throw ConversionFailure(
            'PDF $total halaman; batas ${AppConstants.maxPdfPages} halaman.');
      }
      final base = await _files.subDir('pdf_pages', temp: true);
      outputDir = await Directory(
              '${base.path}/${DateTime.now().millisecondsSinceEpoch}')
          .create(recursive: true);
      final paths = <String>[];
      final last = maxPages == null ? total : math.min(total, maxPages);
      for (var i = 1; i <= last; i++) {
        final page = await doc.getPage(i);
        try {
          final scale = maxSide / math.max(page.width, page.height);
          final img = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
            quality: AppConstants.jpegQuality,
          );
          if (img != null) {
            final f = File('${outputDir.path}/p$i.jpg');
            await f.writeAsBytes(img.bytes);
            paths.add(f.path);
          }
        } finally {
          await page.close();
        }
        onProgress?.call(i, last);
      }
      return (paths: paths, dir: outputDir);
    } catch (_) {
      if (outputDir != null) {
        try {
          await outputDir.delete(recursive: true);
        } catch (_) {}
      }
      rethrow;
    } finally {
      await doc.close();
    }
  }
}
