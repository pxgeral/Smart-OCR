// Uji ujung-ke-ujung opsional pada gambar contoh, memakai Tesseract sebagai
// pengganti ML Kit (yang hanya berjalan di perangkat Android).
//
//   SAMPLE_DIR=/path/berisi/jpg OUT_DIR=/tmp/out flutter test test/e2e_sample_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ocr_converter/features/converter/page_analyzer.dart';
import 'package:smart_ocr_converter/features/converter/page_assembler.dart';
import 'package:smart_ocr_converter/features/export/docx_exporter.dart';
import 'package:smart_ocr_converter/features/export/xlsx_exporter.dart';
import 'package:smart_ocr_converter/models/ocr_result.dart';
import 'package:smart_ocr_converter/models/table_data.dart';

OcrPage _tesseract(String path, int index, {String psm = '3'}) {
  final r = Process.runSync('tesseract', [path, 'stdout', '--psm', psm, 'tsv']);
  final boxes = <OcrBox>[];
  for (final line in (r.stdout as String).split('\n').skip(1)) {
    final f = line.split('\t');
    if (f.length < 12 || f[0] != '5') continue;
    final text = f[11].trim();
    if (text.isEmpty) continue;
    final l = double.parse(f[6]), t = double.parse(f[7]);
    final w = double.parse(f[8]), h = double.parse(f[9]);
    final conf = (double.tryParse(f[10]) ?? 50) / 100;
    boxes.add(OcrBox(text: text, left: l, top: t, right: l + w, bottom: t + h, confidence: conf.clamp(0, 1)));
  }
  return OcrPage(index: index, width: 0, height: 0, boxes: boxes);
}

void main() {
  final dir = Platform.environment['SAMPLE_DIR'];
  final out = Platform.environment['OUT_DIR'] ?? Directory.systemTemp.path;
  test('konversi contoh lengkap', () {
    final files = Directory(dir!)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.jpg'))
        .map((f) => f.path)
        .toList()
      ..sort();
    final work = Directory('$out/work')..createSync(recursive: true);
    final pages = <AssemblyPage>[];
    for (var i = 0; i < files.length; i++) {
      final sw = Stopwatch()..start();
      final a = PageAnalyzer.analyze(
          sourcePath: files[i], workDir: work.path, pageIndex: i, detectTables: true, cellOcr: true);
      final tAnalyze = sw.elapsedMilliseconds;
      final ocr = _tesseract(a.imagePath, i);
      final ma = [for (final m in a.mosaicA) _tesseract(m, 0, psm: '11')];
      final mb = [for (final m in a.mosaicB) _tesseract(m, 0, psm: '11')];
      pages.add(AssemblyPage(a, ocr, ma, mb));
      // ignore: avoid_print
      print('hal ${i + 1}: analisis ${tAnalyze}ms, tabel ${[
        for (final t in a.tables) '${t.rowHeights.length}x${t.colWidths.length}/${t.cells.length}'
      ]}, pita ${a.bands.length}, mosaik ${a.mosaicA.length}');
    }
    final content = PageAssembler.assemble(pages, dictionary: const ['Nasi', 'Ayam', 'Tempe', 'Sayur', 'Bubur', 'Telur']);
    File('$out/hasil.xlsx').writeAsBytesSync(XlsxExporter.build(content));
    File('$out/hasil.docx').writeAsBytesSync(DocxExporter.build(content));
    File('$out/hasil.txt').writeAsStringSync(content.plainText);
    for (final t in content.tables) {
      final n = t.cells.length;
      final chk = t.cells.where((c) => c.status == CellStatus.check).length;
      final err = t.cells.where((c) => c.status == CellStatus.error).length;
      // ignore: avoid_print
      print('tabel ${t.rowCount}x${t.columnCount}, kepala ${t.headerRows}, sel $n, cek $chk, wajib $err, '
          'font ${t.headerFontPt.toStringAsFixed(1)}/${t.bodyFontPt.toStringAsFixed(1)}');
    }
    expect(content.pages, hasLength(files.length));
  }, skip: dir == null ? 'SAMPLE_DIR tidak diset' : false, timeout: const Timeout(Duration(minutes: 10)));
}
