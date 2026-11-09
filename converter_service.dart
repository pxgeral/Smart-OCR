import 'dart:isolate';

import '../../models/converted_content.dart';
import '../../models/enums.dart';
import '../../models/ocr_result.dart';
import '../../models/table_data.dart';
import 'document_builder.dart';
import 'layout_analyzer.dart';
import 'table_detector.dart';

class ConverterService {
  const ConverterService();

  /// [force] null = otomatis (tabel bila >= setengah halaman terdeteksi tabel).
  /// Analisis geometri berjalan di Isolate terpisah.
  Future<ConvertedContent> convert(OcrResult ocr, {DocumentKind? force}) =>
      Isolate.run(() => _convert(ocr, force));
}

ConvertedContent _convert(OcrResult ocr, DocumentKind? force) {
  final layouts = [for (final p in ocr.pages) LayoutAnalyzer.analyze(p)];
  final detected = [
    for (final l in layouts)
      TableDetector.detect(l, force: force == DocumentKind.table),
  ];
  final found = detected.where((t) => t != null).length;
  final kind = force ??
      (found > 0 && found * 2 >= ocr.pages.length
          ? DocumentKind.table
          : DocumentKind.document);

  if (kind == DocumentKind.table) {
    final tables = <TableData>[];
    for (var i = 0; i < detected.length; i++) {
      final t = detected[i] ?? TableDetector.detect(layouts[i], force: true);
      if (t != null) tables.add(t);
    }
    return ConvertedContent(kind: kind, tables: tables);
  }

  final blocks = <DocBlock>[];
  for (final p in ocr.pages) {
    blocks.addAll(DocumentBuilder.build(
      LayoutAnalyzer.analyze(p, cellGap: double.infinity),
    ));
  }
  return ConvertedContent(kind: kind, blocks: blocks);
}
