import 'dart:typed_data';

import '../../core/xml_utils.dart';
import '../../core/zip_writer.dart';
import '../../models/converted_content.dart';
import '../../models/enums.dart';
import '../../models/table_data.dart';

abstract final class DocxExporter {
  static const _contentTypes =
      r'''<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>''';

  static const _rootRels =
      r'''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>''';

  static const _docRels =
      r'''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>''';

  static const _styles =
      r'''<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="id-ID"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults></w:styles>''';

  static const _sect =
      r'''<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>''';

  static const _ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  static const _textWidth = 9638; // lebar teks A4 (dxa)

  static Uint8List build(ConvertedContent c) {
    final body = StringBuffer();
    if (c.kind == DocumentKind.table) {
      for (final t in c.tables) {
        body
          ..write(_table(t))
          ..write('<w:p/>'); // Word wajib punya paragraf setelah tabel
      }
    } else {
      for (final b in c.blocks) {
        body.write(_paragraph(b));
      }
    }
    if (body.isEmpty) body.write('<w:p/>');

    final doc =
        '$xmlHeader<w:document xmlns:w="$_ns"><w:body>$body$_sect</w:body></w:document>';
    return (ZipWriter()
          ..addString('[Content_Types].xml', '$xmlHeader$_contentTypes')
          ..addString('_rels/.rels', '$xmlHeader$_rootRels')
          ..addString('word/document.xml', doc)
          ..addString('word/styles.xml', '$xmlHeader$_styles')
          ..addString('word/_rels/document.xml.rels', '$xmlHeader$_docRels'))
        .build();
  }

  static String _paragraph(DocBlock b) {
    final ind = switch (b.type) {
      BlockType.bullet => '<w:ind w:left="720" w:hanging="360"/>',
      BlockType.numbered => '<w:ind w:left="360"/>',
      _ => '',
    };
    final jc = switch (b.align) {
      BlockAlign.center => '<w:jc w:val="center"/>',
      BlockAlign.right => '<w:jc w:val="right"/>',
      BlockAlign.justify => '<w:jc w:val="both"/>',
      BlockAlign.left => '',
    };
    final size = const {1: 32, 2: 28, 3: 24}[b.level] ?? 24;
    final rpr = b.type == BlockType.heading
        ? '<w:rPr><w:b/><w:sz w:val="$size"/><w:szCs w:val="$size"/></w:rPr>'
        : '';
    final text = b.type == BlockType.bullet ? '• ${b.text}' : b.text;
    return '<w:p><w:pPr>$ind$jc</w:pPr><w:r>$rpr<w:t xml:space="preserve">${xmlEscape(text)}</w:t></w:r></w:p>';
  }

  static String _table(TableData t) {
    final n = t.columnCount;
    if (n == 0) return '';
    final rows = t.normalized;
    final w = _textWidth ~/ n;
    final sb = StringBuffer(
        '<w:tbl><w:tblPr><w:tblW w:w="$_textWidth" w:type="dxa"/><w:tblBorders>');
    for (final e in const ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
      sb.write('<w:$e w:val="single" w:sz="4" w:space="0" w:color="808080"/>');
    }
    sb.write('</w:tblBorders></w:tblPr><w:tblGrid>');
    for (var j = 0; j < n; j++) {
      sb.write('<w:gridCol w:w="$w"/>');
    }
    sb.write('</w:tblGrid>');
    for (var i = 0; i < rows.length; i++) {
      final rpr = t.hasHeader && i == 0 ? '<w:rPr><w:b/></w:rPr>' : '';
      sb.write('<w:tr>');
      for (final cell in rows[i]) {
        sb.write('<w:tc><w:tcPr><w:tcW w:w="$w" w:type="dxa"/></w:tcPr>'
            '<w:p><w:r>$rpr<w:t xml:space="preserve">${xmlEscape(cell)}</w:t></w:r></w:p></w:tc>');
      }
      sb.write('</w:tr>');
    }
    sb.write('</w:tbl>');
    return sb.toString();
  }
}
