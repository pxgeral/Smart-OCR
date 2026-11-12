import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ocr_converter/features/converter/cell_verifier.dart';
import 'package:smart_ocr_converter/models/table_data.dart';

/// Tabel: Menu | Waktu | T1 | T2 | T3 | Rata (1 baris kepala).
VerifyTable _table(List<List<List<String>>> body) {
  final cells = <TableCell>[];
  final cands = <TableCell, List<OcrCandidate>>{};
  const header = ['Nama Menu', 'Waktu', 'Titik 1', 'Titik 2', 'Titik 3', 'Rata Rata'];
  for (var c = 0; c < header.length; c++) {
    final cell = TableCell(row: 0, col: c, hasInk: true);
    cells.add(cell);
    cands[cell] = [OcrCandidate(header[c], 0.95, 'page')];
  }
  for (var r = 0; r < body.length; r++) {
    for (var c = 0; c < body[r].length; c++) {
      final cell = TableCell(row: r + 1, col: c, hasInk: body[r][c].isNotEmpty);
      cells.add(cell);
      cands[cell] = [
        for (var k = 0; k < body[r][c].length; k++)
          OcrCandidate(body[r][c][k], 0.8, const ['page', 'crop', 'norm'][k % 3])
      ];
    }
  }
  final t = TableData(
    colWidths: List.filled(6, 80),
    rowHeights: List.filled(body.length + 1, 30),
    cells: cells,
    headerRows: 1,
  );
  return VerifyTable(t, cands);
}

TableCell _cell(VerifyTable vt, int r, int c) =>
    vt.table.cells.firstWhere((x) => x.row == r && x.col == c);

void main() {
  test('memperbaiki kekeliruan huruf/angka dan format jam', () {
    final vt = _table([
      [['Nasi'], ['09.30'], ['98.6'], ['96.5'], ['93.5'], ['96.2']],
      [['Ayam'], ['05.30'], ['91.7'], ['92.5'], ['94.6'], ['92.93']],
      [['Tempe'], ['O5.4O', '05.40'], ['92.6'], ['88.7'], ['90.4'], ['90.57']],
      [['Sayur'], ['0555'], ['92.7'], ['93.6'], ['91.5'], ['92.6']],
      [['Bubur'], ['06.00'], ['9S.1'], ['93.2'], ['91.0'], ['93.1']],
    ]);
    CellVerifier.verify([vt]);
    expect(_cell(vt, 3, 1).text, '05.40');
    expect(_cell(vt, 4, 1).text, '05.55');
    expect(_cell(vt, 4, 1).status, CellStatus.check);
    expect(_cell(vt, 5, 2).text, '95.1');
    expect(_cell(vt, 2, 5).numeric, isTrue);
    expect(_cell(vt, 1, 0).numeric, isFalse);
  });

  test('menandai rata-rata yang tidak cocok dan memakai bacaan alternatif', () {
    final vt = _table([
      [['Nasi'], ['09.30'], ['98.6'], ['96.5'], ['93.5'], ['96.2']],
      [['Ayam'], ['05.30'], ['91.7'], ['92.5'], ['94.6'], ['92.93']],
      [['Tempe'], ['05.40'], ['92.6'], ['88.7'], ['90.4'], ['90.57']],
      // 33.6 seharusnya 93.6 (alternatif tersedia dari varian lain)
      [['Sayur'], ['05.55'], ['92.7'], ['33.6', '93.6'], ['91.5'], ['92.6']],
      // salah tanpa alternatif -> wajib cek
      [['Bubur'], ['06.00'], ['95.1'], ['93.2'], ['91.0'], ['99.9']],
    ]);
    CellVerifier.verify([vt]);
    expect(_cell(vt, 4, 3).text, '93.6');
    expect(_cell(vt, 4, 3).needsReview, isTrue);
    expect(_cell(vt, 5, 5).status, CellStatus.error);
    expect(_cell(vt, 5, 5).note, contains('93.1'));
    expect(_cell(vt, 1, 5).status, CellStatus.ok);
  });

  test('menyeragamkan ejaan kata yang berulang', () {
    final vt = _table([
      [['Nasi'], ['09.30'], ['98.6'], ['96.5'], ['93.5'], ['96.2']],
      [['Ayam'], ['05.30'], ['91.7'], ['92.5'], ['94.6'], ['92.93']],
      [['Nasi'], ['07.40'], ['93.0'], ['96.1'], ['95.7'], ['94.93']],
      [['Nesi'], ['09.00'], ['93.6'], ['94.6'], ['92.6'], ['93.6']],
      [['Ayam'], ['08.40'], ['92.1'], ['94.6'], ['91.7'], ['92.8']],
    ]);
    CellVerifier.verify([vt]);
    expect(_cell(vt, 4, 0).text, 'Nasi');
    expect(_cell(vt, 4, 0).alternatives, contains('Nesi'));
  });

  test('label teks di kolom angka tidak dianggap salah', () {
    final vt = _table([
      [['Nasi'], ['09.30'], ['98.6'], ['96.5'], ['93.5'], ['96.2']],
      [[], [], ['Batch 2'], [], [], []],
      [['Ayam'], ['05.30'], ['91.7'], ['92.5'], ['94.6'], ['92.93']],
      [['Tempe'], ['05.40'], ['92.6'], ['88.7'], ['90.4'], ['90.57']],
    ]);
    CellVerifier.verify([vt]);
    expect(_cell(vt, 2, 2).text, 'Batch 2');
    expect(_cell(vt, 2, 2).status, isNot(CellStatus.error));
  });

  test('tanggal dengan garis miring terbaca 1 dan desimal koma', () {
    final cells = <TableCell>[];
    final cands = <TableCell, List<OcrCandidate>>{};
    const head = ['Tanggal', 'Masuk', 'Cek'];
    const body = [
      ['04/03/2025', '5,10', '☑'],
      ['0410312025', '4,90', ''],
      ['04/03/2025', '4,8O', ''],
      ['O8/03/2025', '6,00', ''],
    ];
    for (var c = 0; c < 3; c++) {
      final cell = TableCell(row: 0, col: c, hasInk: true);
      cells.add(cell);
      cands[cell] = [OcrCandidate(head[c], 0.9, 'page')];
    }
    for (var r = 0; r < body.length; r++) {
      for (var c = 0; c < 3; c++) {
        final cell = TableCell(row: r + 1, col: c, hasInk: body[r][c].isNotEmpty);
        cells.add(cell);
        cands[cell] = [
          if (c == 2 && r == 0) const OcrCandidate('☑', 1, 'box')
          else if (body[r][c].isNotEmpty) OcrCandidate(body[r][c], 0.8, 'page')
        ];
      }
    }
    final vt = VerifyTable(
        TableData(colWidths: List.filled(3, 80), rowHeights: List.filled(5, 30), cells: cells, headerRows: 1),
        cands);
    CellVerifier.verify([vt]);
    expect(_cell(vt, 2, 0).text, '04/03/2025');
    expect(_cell(vt, 4, 0).text, '08/03/2025');
    expect(_cell(vt, 3, 1).text, '4,80');
    expect(_cell(vt, 1, 1).numeric, isTrue);
    expect(_cell(vt, 1, 2).text, '☑');
    expect(_cell(vt, 1, 2).status, CellStatus.ok);
  });

  test('levenshtein', () {
    expect(CellVerifier.levenshtein('nasi', 'nesi'), 1);
    expect(CellVerifier.levenshtein('tempe', 'tempe'), 0);
    expect(CellVerifier.levenshtein('', 'abc'), 3);
  });
}
