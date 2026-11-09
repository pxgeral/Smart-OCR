import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/format.dart';
import '../../models/converted_content.dart';
import '../../models/enums.dart';
import '../../models/ocr_result.dart';
import '../../services/file_service.dart';
import 'docx_exporter.dart';
import 'pdf_exporter.dart';
import 'xlsx_exporter.dart';

class ExportService {
  ExportService(this._files);
  final FileService _files;

  Future<File> export({
    required OutputType type,
    required String baseName,
    required ConvertedContent content,
    required OcrResult ocr,
    required List<String> images,
  }) async {
    final Uint8List bytes = switch (type) {
      OutputType.docx => DocxExporter.build(content),
      OutputType.xlsx => XlsxExporter.build(content),
      OutputType.txt => Uint8List.fromList(utf8.encode(content.plainText)),
      OutputType.pdf => await PdfExporter.build(ocr, images),
    };
    final dir = await _files.subDir('exports');
    final safe = baseName.replaceAll(RegExp(r'[^\w\- ]'), '_').trim();
    final name = safe.isEmpty ? 'dokumen' : safe;
    return File('${dir.path}/${name}_${stamp(DateTime.now())}.${type.ext}')
        .writeAsBytes(bytes);
  }
}
