import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/xml_utils.dart';
import '../../core/zip_writer.dart';
import '../../models/converted_content.dart';
import '../../models/table_data.dart';

abstract final class XlsxExporter {
  static const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const _r = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  static const _rootRels =
      r'''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''';

  // 2 gaya: 0 = normal, 1 = tebal (header).
  static const _styles =
      r'''<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs></styleSheet>''';

  /// Hanya bilangan bulat tanpa nol di depan yang dijadikan angka, agar
  /// "0812..." (telepon) dan "1.250" (ambigu desimal/ribuan) tidak rusak.
  static final _int = RegExp(r'^-?(0|[1-9]\d{0,14})$');

  static Uint8List build(ConvertedContent c) {
    final tables = c.tables.isNotEmpty
        ? c.tables
        : [
            TableData(rows: [for (final b in c.blocks) [b.text]], hasHeader: false),
          ];
    final n = tables.length;

    final types = StringBuffer(
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
    final sheets = StringBuffer('<workbook xmlns="$_ns" xmlns:r="$_r"><sheets>');
    final rels = StringBuffer(
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    final sheetXml = <String>[];

    for (var i = 0; i < n; i++) {
      final id = i + 1;
      final name = n == 1 ? 'Tabel' : 'Halaman $id';
      types.write(
          '<Override PartName="/xl/worksheets/sheet$id.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
      sheets.write('<sheet name="${xmlEscape(name)}" sheetId="$id" r:id="rId$id"/>');
      rels.write(
          '<Relationship Id="rId$id" Type="$_r/worksheet" Target="worksheets/sheet$id.xml"/>');
      sheetXml.add(_sheet(tables[i]));
    }
    types.write('</Types>');
    sheets.write('</sheets></workbook>');
    rels
      ..write('<Relationship Id="rId${n + 1}" Type="$_r/styles" Target="styles.xml"/>')
      ..write('</Relationships>');

    final out = ZipWriter()
      ..addString('[Content_Types].xml', '$xmlHeader$types')
      ..addString('_rels/.rels', '$xmlHeader$_rootRels')
      ..addString('xl/workbook.xml', '$xmlHeader$sheets')
      ..addString('xl/_rels/workbook.xml.rels', '$xmlHeader$rels')
      ..addString('xl/styles.xml', '$xmlHeader$_styles');
    for (var i = 0; i < n; i++) {
      out.addString('xl/worksheets/sheet${i + 1}.xml', sheetXml[i]);
    }
    return out.build();
  }

  static String _sheet(TableData t) {
    final rows = t.normalized;
    final cols = t.columnCount;
    final sb = StringBuffer('$xmlHeader<worksheet xmlns="$_ns">');
    if (cols > 0) {
      sb.write('<cols>');
      for (var j = 0; j < cols; j++) {
        var len = 8;
        for (final r in rows) {
          len = math.max(len, r[j].length);
        }
        sb.write(
            '<col min="${j + 1}" max="${j + 1}" width="${math.min(60, len + 2)}" customWidth="1"/>');
      }
      sb.write('</cols>');
    }
    sb.write('<sheetData>');
    for (var i = 0; i < rows.length; i++) {
      final header = t.hasHeader && i == 0;
      sb.write('<row r="${i + 1}">');
      for (var j = 0; j < rows[i].length; j++) {
        final v = rows[i][j].trim();
        if (v.isEmpty) continue;
        final ref = '${_col(j)}${i + 1}';
        final style = header ? ' s="1"' : '';
        if (!header && _int.hasMatch(v)) {
          sb.write('<c r="$ref"$style><v>$v</v></c>');
        } else {
          sb.write(
              '<c r="$ref"$style t="inlineStr"><is><t xml:space="preserve">${xmlEscape(v)}</t></is></c>');
        }
      }
      sb.write('</row>');
    }
    sb.write('</sheetData></worksheet>');
    return sb.toString();
  }

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
