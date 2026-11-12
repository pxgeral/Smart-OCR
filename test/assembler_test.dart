import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ocr_converter/features/converter/page_analyzer.dart';
import 'package:smart_ocr_converter/features/converter/page_assembler.dart';
import 'package:smart_ocr_converter/models/ocr_result.dart';
import 'package:smart_ocr_converter/models/table_data.dart';

void main() {
  test('kolom yang garisnya tak terlihat dipulihkan dari celah teks', () {
    // satu kolom lebar 300 px berisi "N  Selasa" per baris (garis NO|HARI hilang)
    const rows = 8;
    final cells = <CellInfo>[];
    final boxes = <OcrBox>[];
    for (var r = 0; r < rows; r++) {
      final y0 = 100.0 + r * 40, y1 = y0 + 40;
      cells.add(CellInfo(
        row: r, col: 0, rowSpan: 1, colSpan: 1,
        box: [100, y0, 400, y1], fill: 0xFFFFFF, hasInk: true, ink: null,
        align: CellAlign.left, inkHeight: 20,
      ));
      cells.add(CellInfo(
        row: r, col: 1, rowSpan: 1, colSpan: 1,
        box: [400, y0, 600, y1], fill: 0xFFFFFF, hasInk: true, ink: null,
        align: CellAlign.left, inkHeight: 20,
      ));
      boxes.add(OcrBox(text: '${r + 1}', left: 110, top: y0 + 10, right: 125, bottom: y0 + 30, confidence: 0.9));
      boxes.add(OcrBox(text: 'Selasa', left: 180, top: y0 + 10, right: 280, bottom: y0 + 30, confidence: 0.9));
      boxes.add(OcrBox(text: '04/03/2025', left: 420, top: y0 + 10, right: 580, bottom: y0 + 30, confidence: 0.9));
    }
    final info = TableInfo(
      colWidths: [300, 200],
      rowHeights: List.filled(rows, 40),
      left: 100,
      top: 100,
      cells: cells,
    );
    final a = PageAnalysis(
      imagePath: '', width: 1000, height: 800, tables: [info], bands: const [],
      slots: const [], mosaicA: const [], mosaicB: const [],
    );
    final content = PageAssembler.assemble([
      AssemblyPage(a, OcrPage(index: 0, width: 1000, height: 800, boxes: boxes), const [], const []),
    ]);
    final t = content.tables.single;
    expect(t.columnCount, 3);
    expect(t.cellAt(3, 0)!.text, '4');
    expect(t.cellAt(3, 1)!.text, 'Selasa');
    expect(t.cellAt(3, 2)!.text, '04/03/2025');
  });
}
