import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ocr_converter/features/export/docx_exporter.dart';
import 'package:smart_ocr_converter/features/export/xlsx_exporter.dart';
import 'package:smart_ocr_converter/models/converted_content.dart';
import 'package:smart_ocr_converter/models/enums.dart';
import 'package:smart_ocr_converter/models/table_data.dart';

ConvertedContent _content() {
  final cells = <TableCell>[
    TableCell(row: 0, col: 0, rowSpan: 2, text: 'No.', fill: 0x2F75B5, bold: true),
    TableCell(row: 0, col: 1, colSpan: 2, text: 'Ulangan 1', fill: 0x9BC2E6, bold: true),
    TableCell(row: 1, col: 1, text: 'Waktu', fill: 0xBDD7EE),
    TableCell(row: 1, col: 2, text: 'Titik 1', fill: 0xBDD7EE),
    TableCell(row: 2, col: 0, text: '1', numeric: true),
    TableCell(row: 2, col: 1, text: '09.30'),
    TableCell(row: 2, col: 2, text: '96.5', numeric: true, status: CellStatus.check, note: 'uji'),
  ];
  final t = TableData(
    colWidths: [60, 120, 120],
    rowHeights: [30, 40, 30],
    cells: cells,
    headerRows: 2,
    left: 100,
    top: 300,
  );
  return ConvertedContent(kind: DocumentKind.table, pages: [
    PageContent(width: 2800, height: 1980, elements: [
      TextElement(DocBlock('I. TABEL PEMANTAUAN', fill: 0x1F3864, fontColor: 0xFFFFFF,
          bold: true, fontPt: 12, top: 100, left: 100, right: 2000, bottom: 140)),
      TableElement(t),
    ]),
  ]);
}

void main() {
  test('xlsx & docx berupa paket zip valid dan memuat gabungan/warna', () {
    final c = _content();
    final x = XlsxExporter.build(c);
    final d = DocxExporter.build(c);
    expect(x.sublist(0, 2), [0x50, 0x4B]);
    expect(d.sublist(0, 2), [0x50, 0x4B]);
    final out = Directory.systemTemp.createTempSync('ocr_export');
    File('${out.path}/t.xlsx').writeAsBytesSync(x);
    File('${out.path}/t.docx').writeAsBytesSync(d);
  });

  test('round-trip ConvertedContent ke map', () {
    final c = _content();
    final back = ConvertedContent.fromMap(c.toMap());
    expect(back.tables.first.cells.length, 7);
    expect(back.tables.first.cells[1].colSpan, 2);
    expect(back.tables.first.cells[0].fill, 0x2F75B5);
    expect(back.reviewCount, 1);
    expect(back.blocks.first.fill, 0x1F3864);
  });
}
