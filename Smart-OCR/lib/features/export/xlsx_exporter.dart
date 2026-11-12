import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/raster.dart';
import '../../core/xml_utils.dart';
import '../../core/zip_writer.dart';
import '../../models/app_settings.dart';
import '../../models/converted_content.dart';
import '../../models/table_data.dart';

/// Excel dengan tata letak menyerupai sumber: satu lembar per halaman,
/// lebar kolom & tinggi baris proporsional, sel gabungan, warna latar,
/// garis, perataan, ukuran huruf, plus lembar "Verifikasi".
abstract final class XlsxExporter {
  static const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const _r = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  static const _rootRels =
      r'''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''';

  static final _int = RegExp(r'^-?(0|[1-9]\d{0,14})$');
  static final _dec = RegExp(r'^-?\d{1,9}\.(\d{1,6})$');

  static Uint8List build(ConvertedContent c,
      {ExportOptions options = const ExportOptions()}) {
    final styles = _Styles();
    final sheets = <(String, String)>[]; // name, xml
    final review = <_ReviewRow>[];

    final pages = c.pages.isEmpty
        ? [PageContent(width: 1000, height: 1414, elements: const [])]
        : c.pages;
    for (var i = 0; i < pages.length; i++) {
      final name = pages.length == 1 ? 'Halaman 1' : 'Hal ${i + 1}';
      sheets.add((name, _SheetBuilder(pages[i], styles, options, name, i, review).build()));
    }
    if (options.reviewSheet && review.isNotEmpty) {
      sheets.add(('Verifikasi', _reviewSheet(review, styles)));
    }

    final types = StringBuffer(
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
    final wb = StringBuffer('<workbook xmlns="$_ns" xmlns:r="$_r"><sheets>');
    final rels = StringBuffer(
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (var i = 0; i < sheets.length; i++) {
      final id = i + 1;
      types.write(
          '<Override PartName="/xl/worksheets/sheet$id.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
      wb.write('<sheet name="${xmlEscape(sheets[i].$1)}" sheetId="$id" r:id="rId$id"/>');
      rels.write('<Relationship Id="rId$id" Type="$_r/worksheet" Target="worksheets/sheet$id.xml"/>');
    }
    types.write('</Types>');
    wb.write('</sheets></workbook>');
    rels
      ..write('<Relationship Id="rId${sheets.length + 1}" Type="$_r/styles" Target="styles.xml"/>')
      ..write('</Relationships>');

    final out = ZipWriter()
      ..addString('[Content_Types].xml', '$xmlHeader$types')
      ..addString('_rels/.rels', '$xmlHeader$_rootRels')
      ..addString('xl/workbook.xml', '$xmlHeader$wb')
      ..addString('xl/_rels/workbook.xml.rels', '$xmlHeader$rels')
      ..addString('xl/styles.xml', '$xmlHeader${styles.xml()}');
    for (var i = 0; i < sheets.length; i++) {
      out.addString('xl/worksheets/sheet${i + 1}.xml', sheets[i].$2);
    }
    return out.build();
  }

  static String _reviewSheet(List<_ReviewRow> rows, _Styles st) {
    final head = st.xf(bold: true, fill: 0xD9E1F2, border: true, size: 11);
    final body = st.xf(border: true, size: 10, wrap: true);
    final err = st.xf(border: true, size: 10, fill: 0xF8CBAD, wrap: true);
    final chk = st.xf(border: true, size: 10, fill: 0xFFE699, wrap: true);
    final link = st.xf(border: true, size: 10, color: 0x0563C1, underline: true);
    final sb = StringBuffer('$xmlHeader<worksheet xmlns="$_ns" xmlns:r="$_r">');
    sb.write('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>');
    sb.write('<cols>');
    const widths = [10, 10, 10, 22, 12, 46, 30];
    for (var j = 0; j < widths.length; j++) {
      sb.write('<col min="${j + 1}" max="${j + 1}" width="${widths[j]}" customWidth="1"/>');
    }
    sb.write('</cols><sheetData>');
    const titles = ['Lembar', 'Sel', 'Buka', 'Isi', 'Status', 'Catatan', 'Bacaan lain'];
    sb.write('<row r="1">');
    for (var j = 0; j < titles.length; j++) {
      sb.write(_str('${_col(j)}1', titles[j], head));
    }
    sb.write('</row>');
    final links = StringBuffer();
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final n = i + 2;
      final s = r.cell.status == CellStatus.error ? err : chk;
      sb
        ..write('<row r="$n">')
        ..write(_str('A$n', r.sheet, body))
        ..write(_str('B$n', r.ref, body))
        ..write(_str('C$n', 'lihat', link))
        ..write(_str('D$n', r.cell.text, body))
        ..write(_str('E$n', r.cell.status == CellStatus.error ? 'Wajib cek' : 'Perlu cek', s))
        ..write(_str('F$n', r.cell.note, body))
        ..write(_str('G$n', r.cell.alternatives.take(4).join(' / '), body))
        ..write('</row>');
      links.write('<hyperlink ref="C$n" location="${xmlEscape("'${r.sheet}'!${r.ref}")}" display="lihat"/>');
    }
    sb.write('</sheetData>');
    sb.write('<autoFilter ref="A1:G${rows.length + 1}"/>');
    if (links.isNotEmpty) sb.write('<hyperlinks>$links</hyperlinks>');
    sb.write('</worksheet>');
    return sb.toString();
  }

  static String _str(String ref, String v, int style) =>
      '<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${xmlEscape(v)}</t></is></c>';

  static String _col(int j) {
    var s = '';
    var n = j + 1;
    while (n > 0) {
      s = String.fromCharCode(65 + (n - 1) % 26) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }
}

class _ReviewRow {
  _ReviewRow(this.sheet, this.ref, this.cell);
  final String sheet, ref;
  final TableCell cell;
}

class _SheetBuilder {
  _SheetBuilder(this.page, this.st, this.opt, this.name, this.index, this.review);

  final PageContent page;
  final _Styles st;
  final ExportOptions opt;
  final String name;
  final int index;
  final List<_ReviewRow> review;

  /// Skala agar huruf tabel tetap terbaca di layar (min. ~10 pt); proporsi
  /// tetap sama dan cetak tetap muat satu halaman lebar (fitToWidth).
  late final double zoom = () {
    final fonts = [for (final t in page.tables) t.bodyFontPt].where((f) => f > 0);
    if (fonts.isEmpty) return 1.0;
    final minF = fonts.reduce(math.min);
    return (10 / minF).clamp(1.0, 1.6).toDouble();
  }();

  late final double pxToPt =
      zoom * (page.landscape ? 842.0 : 595.0) / math.max(1.0, page.width);

  final _rows = <int, StringBuffer>{};
  final _heights = <int, double>{};
  final _merges = <String>[];

  String build() {
    final els = [...page.elements]..sort((a, b) => a.top.compareTo(b.top));
    final grid = _grid(els);
    final colCount = grid.length - 1;
    var cur = 1;
    double? prevBottom;
    var frozen = 0;
    final singleTable = els.whereType<TableElement>().length == 1;
    for (final e in els) {
      final gapPx = prevBottom == null ? 0.0 : e.top - prevBottom;
      if (prevBottom != null && gapPx * pxToPt > 10) {
        _heights[cur] = math.min(40.0, math.max(8.0, gapPx * pxToPt * 0.6));
        cur++;
      }
      switch (e) {
        case TextElement(:final block):
          cur = _paragraph(block, cur, colCount, grid);
        case TableElement(:final table):
          final start = cur;
          cur = _table(table, cur, grid);
          if (singleTable && table.headerRows > 0) frozen = start + table.headerRows - 1;
      }
      prevBottom = e.bottom;
    }

    final sb = StringBuffer('$xmlHeader<worksheet xmlns="${XlsxExporter._ns}" xmlns:r="${XlsxExporter._r}">');
    sb.write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>');
    sb.write('<sheetViews><sheetView workbookViewId="0" zoomScale="100">');
    if (frozen > 0) {
      sb.write('<pane ySplit="$frozen" topLeftCell="A${frozen + 1}" activePane="bottomLeft" state="frozen"/>');
    }
    sb.write('</sheetView></sheetViews>');
    sb.write('<sheetFormatPr defaultRowHeight="15"/>');
    sb.write('<cols>');
    for (var j = 0; j < colCount; j++) {
      final wpx = grid[j + 1] - grid[j];
      final w = math.max(1.2, wpx * pxToPt / 5.25);
      sb.write('<col min="${j + 1}" max="${j + 1}" width="${w.toStringAsFixed(2)}" customWidth="1"/>');
    }
    sb.write('</cols><sheetData>');
    final keys = {..._rows.keys, ..._heights.keys}.toList()..sort();
    for (final r in keys) {
      final h = _heights[r];
      sb.write('<row r="$r"${h != null ? ' ht="${h.toStringAsFixed(1)}" customHeight="1"' : ''}>');
      sb.write(_rows[r]?.toString() ?? '');
      sb.write('</row>');
    }
    sb.write('</sheetData>');
    if (_merges.isNotEmpty) {
      sb.write('<mergeCells count="${_merges.length}">');
      for (final m in _merges) {
        sb.write('<mergeCell ref="$m"/>');
      }
      sb.write('</mergeCells>');
    }
    sb.write('<pageMargins left="0.3" right="0.3" top="0.4" bottom="0.4" header="0.2" footer="0.2"/>');
    sb.write('<pageSetup paperSize="9" orientation="${page.landscape ? 'landscape' : 'portrait'}" fitToWidth="1" fitToHeight="0"/>');
    sb.write('</worksheet>');
    return sb.toString();
  }

  /// Batas kolom gabungan semua tabel di halaman (px), plus tepi konten.
  List<double> _grid(List<PageElement> els) {
    if (els.isEmpty) return [0, page.width * 0.9];
    var left = els.map((e) => e.left).reduce(math.min);
    var right = els.map((e) => e.right).reduce(math.max);
    if (right - left < page.width * 0.3) {
      left = math.min(left, page.width * 0.05);
      right = math.max(right, page.width * 0.95);
    }
    final pos = <double>[left, right];
    for (final e in els) {
      if (e is TableElement) {
        var x = e.table.left;
        pos.add(x);
        for (final w in e.table.colWidths) {
          x += w;
          pos.add(x);
        }
      }
    }
    pos.sort();
    final tol = math.max(4.0, page.width * 0.006);
    final out = <double>[];
    for (final p in pos) {
      if (out.isEmpty || p - out.last > tol) {
        out.add(p);
      }
    }
    if (out.length < 2) return [left, right];
    return out;
  }

  int _gi(List<double> grid, double x) {
    var best = 0;
    var bd = double.infinity;
    for (var i = 0; i < grid.length; i++) {
      final d = (grid[i] - x).abs();
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  void _put(int row, int col, String xml) {
    (_rows[row] ??= StringBuffer()).write(xml);
  }

  int _paragraph(DocBlock b, int row, int colCount, List<double> grid) {
    final size = (b.fontPt > 0 ? b.fontPt : 11.0) * zoom;
    final fill = opt.keepColors ? b.fill : null;
    final s = st.xf(
      bold: b.bold,
      size: size,
      color: opt.keepColors ? b.fontColor : null,
      fill: fill,
      h: switch (b.align) {
        BlockAlign.center => 'center',
        BlockAlign.right => 'right',
        _ => 'left',
      },
      v: 'center',
      wrap: true,
    );
    final totalPt = (grid.last - grid.first) * pxToPt;
    final lines = b.text.split('\n').fold<int>(
        0, (n, l) => n + math.max(1, (l.length * size * 0.5 / math.max(40.0, totalPt)).ceil()));
    _heights[row] = math.max(13.0, size * 1.35) * lines;
    _put(row, 0, XlsxExporter._str('A$row', b.text, s));
    if (colCount > 1) {
      for (var j = 1; j < colCount; j++) {
        _put(row, j, '<c r="${XlsxExporter._col(j)}$row" s="$s"/>');
      }
      _merges.add('A$row:${XlsxExporter._col(colCount - 1)}$row');
    }
    return row + 1;
  }

  int _table(TableData t, int row0, List<double> grid) {
    // batas kolom tabel -> indeks grid lembar
    final bx = <int>[];
    var x = t.left;
    bx.add(_gi(grid, x));
    for (final w in t.colWidths) {
      x += w;
      bx.add(_gi(grid, x));
    }
    for (var r = 0; r < t.rowCount; r++) {
      _heights[row0 + r] = math.max(12.0, t.rowHeights[r] * pxToPt);
    }
    // sel per baris harus urut kolom: kumpulkan dulu
    final pending = <int, List<(int, String)>>{};
    for (final c in t.cells) {
      final header = c.row < t.headerRows;
      var fill = opt.keepColors ? c.fill : null;
      if (opt.markReview && c.needsReview) {
        fill = c.status == CellStatus.error ? 0xF8CBAD : 0xFFE699;
      }
      final s = st.xf(
        bold: c.bold || header,
        size: (header ? t.headerFontPt : t.bodyFontPt) * zoom,
        color: opt.keepColors ? c.fontColor : null,
        fill: fill,
        border: t.ruled,
        h: header
            ? 'center'
            : switch (c.align) {
                CellAlign.center => 'center',
                CellAlign.right => 'right',
                CellAlign.left => 'left',
              },
        v: 'center',
        wrap: true,
        numFmt: _numFmt(c),
      );
      final c0 = bx[c.col.clamp(0, bx.length - 1)];
      final c1 = math.max(c0, bx[(c.col + c.colSpan).clamp(0, bx.length - 1)] - 1);
      final r0 = row0 + c.row, r1 = row0 + c.row + c.rowSpan - 1;
      final ref = '${XlsxExporter._col(c0)}$r0';
      for (var rr = r0; rr <= r1; rr++) {
        for (var cc = c0; cc <= c1; cc++) {
          final xml = rr == r0 && cc == c0
              ? _value(ref, c, s)
              : '<c r="${XlsxExporter._col(cc)}$rr" s="$s"/>';
          (pending[rr] ??= []).add((cc, xml));
        }
      }
      if (r1 > r0 || c1 > c0) _merges.add('$ref:${XlsxExporter._col(c1)}$r1');
      if (c.needsReview) review.add(_ReviewRow(name, ref, c));
    }
    for (final e in pending.entries) {
      final list = e.value..sort((a, b) => a.$1.compareTo(b.$1));
      final seen = <int>{};
      for (final (col, xml) in list) {
        if (seen.add(col)) _put(e.key, col, xml);
      }
    }
    return row0 + t.rowCount;
  }

  int _numFmt(TableCell c) {
    if (!c.numeric) return 0;
    final m = XlsxExporter._dec.firstMatch(c.text.trim());
    if (m == null) return XlsxExporter._int.hasMatch(c.text.trim()) ? 1 : 0;
    return st.numFmt('0.${'0' * m.group(1)!.length}');
  }

  String _value(String ref, TableCell c, int s) {
    final v = c.text.trim();
    if (v.isEmpty) return '<c r="$ref" s="$s"/>';
    if (c.numeric &&
        (XlsxExporter._int.hasMatch(v) || XlsxExporter._dec.hasMatch(v))) {
      return '<c r="$ref" s="$s"><v>$v</v></c>';
    }
    return XlsxExporter._str(ref, v, s);
  }
}

/// Registri gaya (font, isian, garis, format angka) dengan deduplikasi.
class _Styles {
  final _fonts = <String>['<font><sz val="11"/><name val="Calibri"/><family val="2"/></font>'];
  final _fontIdx = <String, int>{};
  final _fills = <String>[
    '<fill><patternFill patternType="none"/></fill>',
    '<fill><patternFill patternType="gray125"/></fill>',
  ];
  final _fillIdx = <int, int>{};
  final _numFmts = <String, int>{};
  final _xfs = <String>['<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'];
  final _xfIdx = <String, int>{};

  int numFmt(String code) => _numFmts.putIfAbsent(code, () => 164 + _numFmts.length);

  int _font(bool bold, double size, int? color, bool underline) {
    final sz = (size * 2).round() / 2;
    final key = '$bold|$sz|$color|$underline';
    return _fontIdx.putIfAbsent(key, () {
      _fonts.add('<font>${bold ? '<b/>' : ''}${underline ? '<u/>' : ''}<sz val="$sz"/>'
          '${color != null ? '<color rgb="FF${colorHex(color)}"/>' : ''}'
          '<name val="Calibri"/><family val="2"/></font>');
      return _fonts.length - 1;
    });
  }

  int _fill(int? rgb) {
    if (rgb == null) return 0;
    return _fillIdx.putIfAbsent(rgb, () {
      _fills.add('<fill><patternFill patternType="solid"><fgColor rgb="FF${colorHex(rgb)}"/>'
          '<bgColor indexed="64"/></patternFill></fill>');
      return _fills.length - 1;
    });
  }

  int xf({
    bool bold = false,
    double size = 11,
    int? color,
    int? fill,
    bool border = false,
    String h = '',
    String v = '',
    bool wrap = false,
    bool underline = false,
    int numFmt = 0,
  }) {
    final f = _font(bold, size, color, underline);
    final fi = _fill(fill);
    final b = border ? 1 : 0;
    final key = '$f|$fi|$b|$h|$v|$wrap|$numFmt';
    return _xfIdx.putIfAbsent(key, () {
      final align = (h.isEmpty && v.isEmpty && !wrap)
          ? ''
          : '<alignment${h.isNotEmpty ? ' horizontal="$h"' : ''}'
              '${v.isNotEmpty ? ' vertical="$v"' : ''}${wrap ? ' wrapText="1"' : ''}/>';
      _xfs.add('<xf numFmtId="$numFmt" fontId="$f" fillId="$fi" borderId="$b" xfId="0"'
          '${numFmt != 0 ? ' applyNumberFormat="1"' : ''} applyFont="1"'
          '${fi != 0 ? ' applyFill="1"' : ''}${b != 0 ? ' applyBorder="1"' : ''}'
          '${align.isNotEmpty ? ' applyAlignment="1">$align</xf>' : '/>'}');
      return _xfs.length - 1;
    });
  }

  String xml() {
    final sb = StringBuffer('<styleSheet xmlns="${XlsxExporter._ns}">');
    if (_numFmts.isNotEmpty) {
      sb.write('<numFmts count="${_numFmts.length}">');
      _numFmts.forEach((code, id) {
        sb.write('<numFmt numFmtId="$id" formatCode="${xmlEscape(code)}"/>');
      });
      sb.write('</numFmts>');
    }
    sb.write('<fonts count="${_fonts.length}">${_fonts.join()}</fonts>');
    sb.write('<fills count="${_fills.length}">${_fills.join()}</fills>');
    sb.write('<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>'
        '<border><left style="thin"><color rgb="FF000000"/></left><right style="thin"><color rgb="FF000000"/></right>'
        '<top style="thin"><color rgb="FF000000"/></top><bottom style="thin"><color rgb="FF000000"/></bottom><diagonal/></border></borders>');
    sb.write('<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>');
    sb.write('<cellXfs count="${_xfs.length}">${_xfs.join()}</cellXfs>');
    sb.write('<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>');
    sb.write('</styleSheet>');
    return sb.toString();
  }
}
