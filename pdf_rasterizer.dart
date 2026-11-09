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
  }) async {
    final doc = await PdfDocument.openFile(pdfPath);
    try {
      final total = doc.pagesCount;
      if (total > AppConstants.maxPdfPages) {
        throw ConversionFailure(
            'PDF $total halaman; batas ${AppConstants.maxPdfPages} halaman.');
      }
      final base = await _files.subDir('pdf_pages', temp: true);
      final dir = await Directory(
              '${base.path}/${DateTime.now().millisecondsSinceEpoch}')
          .create(recursive: true);
      final paths = <String>[];
      for (var i = 1; i <= total; i++) {
        final page = await doc.getPage(i);
        try {
          final scale = AppConstants.maxImageSide /
              math.max(page.width, page.height);
          final img = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
            quality: AppConstants.jpegQuality,
          );
          if (img != null) {
            final f = File('${dir.path}/p$i.jpg');
            await f.writeAsBytes(img.bytes);
            paths.add(f.path);
          }
        } finally {
          await page.close();
        }
        onProgress?.call(i, total);
      }
      return (paths: paths, dir: dir);
    } finally {
      await doc.close();
    }
  }
}
