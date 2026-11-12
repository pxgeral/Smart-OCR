import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/raster.dart';
import '../../core/xml_utils.dart';
import '../../core/zip_writer.dart';
import '../../models/app_settings.dart';
import '../../models/converted_content.dart';
import '../../models/table_data.dart';

/// Word dengan tata letak menyerupai sumber: orientasi per halaman, posisi &
/// lebar tabel proporsional, sel gabungan (gridSpan/vMerge), warna latar,
/// garis, ukuran huruf, perataan, dan pita judul berwarna.
abstract final class DocxExporter {
  static const _contentTypes =
      r'''<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>''';

  static const _rootRels =
      r'''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>''';

  static const _docRels =
      r'''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>''';

  static const _styles =
      r'''<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="id-ID"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="80" w:line="252" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style><w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="57" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="57" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style></w:styles>''';

  static const _ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  static const _margin = 720; // 1,27 cm

  static Uint8List build(ConvertedContent c,
      {ExportOptions options = const ExportOptions()}) {
    final body = StringBuffer();
    final pages = c.pages;
    for (var i = 0; i < pages.length; i++) {
      final p = pages[i];
      _page(body, p, options);
      if (i < pages.length - 1) {
        body.write('<w:p><w:pPr>${_sect(p.landscape)}</w:pPr></w:p>');
      }
    }
    if (body.isEmpty) body.write('<w:p/>');
    final last = pages.isEmpty ? false : pages.last.landscape;
    final doc =
        '$xmlHeader<w:document xmlns:w="$_ns"><w:body>$body${_sect(last)}</w:body></w:document>';
    return (ZipWriter()
          ..addString('[Content_Types].xml', '$xmlHeader$_contentTypes')
          ..addString('_rels/.rels', '$xmlHeader$_rootRels')
          ..addString('word/document.xml', doc)
          ..addString('word/styles.xml', '$xmlHeader$_styles')
          ..addString('word/_rels/document.xml.rels', '$xmlHeader$_docRels'))
        .build();
  }

  static String _sect(bool landscape) {
    final w = landscape ? 16838 : 11906, h = landscape ? 11906 : 16838;
    return '<w:sectPr><w:pgSz w:w="$w" w:h="$h"${landscape ? ' w:orient="landscape"' : ''}/>'
        '<w:pgMar w:top="$_margin" w:right="$_margin" w:bottom="$_margin" w:left="$_margin" '
        'w:header="400" w:footer="400" w:gutter="0"/></w:sectPr>';
  }

  static void _page(StringBuffer out, PageContent p, ExportOptions opt) {
    final els = [...p.elements]..sort((a, b) => a.top.compareTo(b.top));
    if (els.isEmpty) {
      out.write('<w:p/>');
      return;
    }
    final textW = (p.landscape ? 16838 : 11906) - 2 * _margin;
    var left = els.map((e) => e.left).reduce(math.min);
    var right = els.map((e) => e.right).reduce(math.max);
    if (right - left < p.width * 0.5) {
      left = math.min(left, p.width * 0.06);
      right = math.max(right, p.width * 0.94);
    }
    final tw = textW / math.max(1.0, right - left); // twips per px
    final pxToPt = (p.landscape ? 842.0 : 595.0) / math.max(1.0, p.width);
    double? prevBottom;
    for (final e in els) {
      final gap = prevBottom == null ? 0.0 : math.max(0.0, e.top - prevBottom);
      final before = math.min(720, (gap * tw * 0.6).round());
      switch (e) {
        case TextElement(:final block):
          out.write(_paragraph(block, before, left, tw, textW, opt));
        case TableElement(:final table):
          if (before > 60) {
            out.write('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="${math.max(20, before)}" w:lineRule="exact"/></w:pPr></w:p>');
          }
          out
            ..write(_table(table, left, tw, textW, pxToPt, opt))
            ..write('<w:p><w:pPr><w:spacing w:after="0" w:line="120" w:lineRule="exact"/></w:pPr></w:p>');
      }
      prevBottom = e.bottom;
    }
  }

  static String _runProps({bool bold = false, double pt = 0, int? color}) {
    final sb = StringBuffer();
    if (bold) sb.write('<w:b/><w:bCs/>');
    if (color != null) sb.write('<w:color w:val="${colorHex(color)}"/>');
    if (pt > 0) {
      final hp = (pt * 2).round();
      sb.write('<w:sz w:val="$hp"/><w:szCs w:val="$hp"/>');
    }
    return sb.isEmpty ? '' : '<w:rPr>$sb</w:rPr>';
  }

  static String _runs(String text, String rpr) {
    final lines = text.split('\n');
    final sb = StringBuffer('<w:r>$rpr');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) sb.write('<w:br/>');
      sb.write('<w:t xml:space="preserve">${xmlEscape(lines[i])}</w:t>');
    }
    sb.write('</w:r>');
    return sb.toString();
  }

  static String _paragraph(DocBlock b, int before, double left, double tw,
      int textW, ExportOptions opt) {
    final ppr = StringBuffer();
    final fill = opt.keepColors ? b.fill : null;
    if (fill != null) {
      ppr.write('<w:shd w:val="clear" w:color="auto" w:fill="${colorHex(fill)}"/>');
    }
    ppr.write('<w:spacing w:before="$before" w:after="40"/>');
    final indent = ((b.left - left) * tw).round();
    switch (b.type) {
      case BlockType.bullet:
        ppr.write('<w:ind w:left="${math.max(360, indent) + 360}" w:hanging="360"/>');
      case BlockType.numbered:
        ppr.write('<w:ind w:left="${math.max(360, indent)}"/>');
      default:
        if (b.align == BlockAlign.left && indent > textW * 0.03 && fill == null) {
          ppr.write('<w:ind w:left="${math.min(indent, textW ~/ 2)}"/>');
        }
    }
    final jc = switch (b.align) {
      BlockAlign.center => 'center',
      BlockAlign.right => 'right',
      BlockAlign.justify => 'both',
      BlockAlign.left => '',
    };
    if (jc.isNotEmpty) ppr.write('<w:jc w:val="$jc"/>');
    final defaultPt = switch (b.type) {
      BlockType.heading => const {1: 16.0, 2: 14.0, 3: 12.0}[b.level] ?? 12.0,
      _ => 0.0,
    };
    final rpr = _runProps(
      bold: b.bold || b.type == BlockType.heading,
      pt: b.fontPt > 0 ? b.fontPt : defaultPt,
      color: opt.keepColors ? b.fontColor : null,
    );
    final text = b.type == BlockType.bullet ? '• ${b.text}' : b.text;
    return '<w:p><w:pPr>$ppr</w:pPr>${_runs(text, rpr)}</w:p>';
  }

  static String _table(TableData t, double left, double tw, int textW,
      double pxToPt, ExportOptions opt) {
    final n = t.columnCount;
    if (n == 0 || t.rowCount == 0) return '';
    var widths = [for (final w in t.colWidths) math.max(120, (w * tw).round())];
    final total = widths.fold<int>(0, (a, b) => a + b);
    if (total > textW) {
      widths = [for (final w in widths) math.max(100, w * textW ~/ total)];
    }
    final sum = widths.fold<int>(0, (a, b) => a + b);
    final ind = math.max(0, math.min(((t.left - left) * tw).round(), textW - sum));
    final border = t.ruled ? 'single' : 'nil';
    final sb = StringBuffer('<w:tbl><w:tblPr><w:tblW w:w="$sum" w:type="dxa"/>'
        '<w:tblInd w:w="$ind" w:type="dxa"/><w:tblBorders>');
    for (final e in const ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
      sb.write('<w:$e w:val="$border" w:sz="4" w:space="0" w:color="000000"/>');
    }
    sb.write('</w:tblBorders><w:tblLayout w:type="fixed"/>'
        '<w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="40" w:type="dxa"/>'
        '<w:bottom w:w="0" w:type="dxa"/><w:right w:w="40" w:type="dxa"/></w:tblCellMar>'
        '<w:tblLook w:val="0000"/></w:tblPr><w:tblGrid>');
    for (final w in widths) {
      sb.write('<w:gridCol w:w="$w"/>');
    }
    sb.write('</w:tblGrid>');

    // peta sel penutup tiap posisi grid
    final owner = List.generate(t.rowCount, (_) => List<TableCell?>.filled(n, null));
    for (final c in t.cells) {
      for (var r = c.row; r < math.min(t.rowCount, c.row + c.rowSpan); r++) {
        for (var k = c.col; k < math.min(n, c.col + c.colSpan); k++) {
          owner[r][k] = c;
        }
      }
    }
    for (var r = 0; r < t.rowCount; r++) {
      final header = r < t.headerRows;
      final hTw = math.max(200, (t.rowHeights[r] * tw).round());
      sb.write('<w:tr><w:trPr><w:trHeight w:val="$hTw" w:hRule="atLeast"/>'
          '${header ? '<w:tblHeader/>' : ''}<w:cantSplit/></w:trPr>');
      var k = 0;
      while (k < n) {
        final c = owner[r][k];
        if (c == null) {
          sb.write('<w:tc><w:tcPr><w:tcW w:w="${widths[k]}" w:type="dxa"/></w:tcPr><w:p/></w:tc>');
          k++;
          continue;
        }
        final span = math.min(c.colSpan, n - c.col);
        final start = c.col;
        if (start != k) {
          // sel gabungan yang tidak mulai di sini (seharusnya tidak terjadi)
          sb.write('<w:tc><w:tcPr><w:tcW w:w="${widths[k]}" w:type="dxa"/></w:tcPr><w:p/></w:tc>');
          k++;
          continue;
        }
        final w = widths.sublist(start, start + span).fold<int>(0, (a, b) => a + b);
        final tcPr = StringBuffer('<w:tcW w:w="$w" w:type="dxa"/>');
        if (span > 1) tcPr.write('<w:gridSpan w:val="$span"/>');
        if (c.rowSpan > 1) {
          tcPr.write(r == c.row ? '<w:vMerge w:val="restart"/>' : '<w:vMerge/>');
        }
        var fill = opt.keepColors ? c.fill : null;
        if (opt.markReview && c.needsReview) {
          fill = c.status == CellStatus.error ? 0xF8CBAD : 0xFFE699;
        }
        if (fill != null) {
          tcPr.write('<w:shd w:val="clear" w:color="auto" w:fill="${colorHex(fill)}"/>');
        }
        tcPr.write('<w:vAlign w:val="center"/>');
        final cellHeader = c.row < t.headerRows;
        final jc = cellHeader
            ? 'center'
            : switch (c.align) {
                CellAlign.center => 'center',
                CellAlign.right => 'right',
                CellAlign.left => 'left',
              };
        final pt = cellHeader ? t.headerFontPt : t.bodyFontPt;
        final para = r == c.row && c.text.isNotEmpty
            ? '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
                '<w:jc w:val="$jc"/></w:pPr>'
                '${_runs(c.text, _runProps(bold: c.bold || cellHeader, pt: pt, color: opt.keepColors ? c.fontColor : null))}</w:p>'
            : '<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr></w:p>';
        sb.write('<w:tc><w:tcPr>$tcPr</w:tcPr>$para</w:tc>');
        k += span;
      }
      sb.write('</w:tr>');
    }
    sb.write('</w:tbl>');
    return sb.toString();
  }
}
