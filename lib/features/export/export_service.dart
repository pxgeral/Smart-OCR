import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../core/format.dart';
import '../../models/app_settings.dart';
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

  /// [replacePath] diisi saat ekspor ulang dari layar tinjau agar file lama
  /// diganti (nama tetap).
  Future<File> export({
    required OutputType type,
    required String baseName,
    required ConvertedContent content,
    OcrResult? ocr,
    List<String> images = const [],
    ExportOptions options = const ExportOptions(),
    String? replacePath,
  }) async {
    final Uint8List bytes = switch (type) {
      OutputType.docx => await _docx(content, options),
      OutputType.xlsx => await _xlsx(content, options),
      OutputType.txt => Uint8List.fromList(utf8.encode(content.plainText)),
      OutputType.pdf => await PdfExporter.build(
          ocr ?? _ocrFromContent(content), images),
    };
    if (replacePath != null && replacePath.endsWith('.${type.ext}')) {
      return File(replacePath).writeAsBytes(bytes);
    }
    final dir = await _files.subDir('exports');
    final safe = baseName.replaceAll(RegExp(r'[^\w\- ]'), '_').trim();
    final name = safe.isEmpty ? 'dokumen' : safe;
    return File('${dir.path}/${name}_${stamp(DateTime.now())}.${type.ext}')
        .writeAsBytes(bytes);
  }

  static Future<Uint8List> _docx(ConvertedContent c, ExportOptions o) =>
      Isolate.run(() => DocxExporter.build(c, options: o));

  static Future<Uint8List> _xlsx(ConvertedContent c, ExportOptions o) =>
      Isolate.run(() => XlsxExporter.build(c, options: o));

  /// PDF searchable dari isi yang sudah dikoreksi: teks sel diletakkan di
  /// posisi selnya.
  static OcrResult _ocrFromContent(ConvertedContent c) => OcrResult(
        engine: OcrEngineId.mlkit,
        pages: [
          for (var i = 0; i < c.pages.length; i++)
            OcrPage(
              index: i,
              width: c.pages[i].width,
              height: c.pages[i].height,
              boxes: [
                for (final b in c.pages[i].blocks)
                  OcrBox(
                      text: b.text.replaceAll('\n', ' '),
                      left: b.left,
                      top: b.top,
                      right: b.right,
                      bottom: b.bottom),
                for (final t in c.pages[i].tables)
                  for (final cell in t.cells)
                    if (cell.text.isNotEmpty && cell.box.length == 4)
                      OcrBox(
                        text: cell.text.replaceAll('\n', ' '),
                        left: cell.box[0] + 4,
                        top: cell.box[1] + 2,
                        right: cell.box[2] - 4,
                        bottom: cell.box[3] - 2,
                      ),
              ],
            ),
        ],
      );
}
