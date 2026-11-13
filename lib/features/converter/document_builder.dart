import 'dart:math' as math;

import '../../models/converted_content.dart';
import 'layout_analyzer.dart';

/// Baris OCR -> paragraf, heading, bullet, nomor, alignment, ukuran huruf,
/// dan posisi (untuk diurutkan bersama tabel).
abstract final class DocumentBuilder {
  static final _bullet = RegExp(r'^[\-•·●○\*>]\s+');
  static final _numbered = RegExp(r'^\(?\d{1,3}[.)]\s+');
  static final _upper = RegExp(r'[A-Z]');

  /// [pxToPt] = faktor konversi px gambar -> pt halaman (0 = abaikan ukuran).
  /// [styleAt] memberi warna latar/tulisan untuk baris pada posisi tertentu
  /// (pita judul berwarna).
  static List<DocBlock> build(
    PageLayout layout, {
    double pxToPt = 0,
    ({int? fill, int? color})? Function(LayoutRow row)? styleAt,
  }) {
    final rows = layout.rows;
    if (rows.isEmpty) return [];

    final h = layout.lineHeight;
    final minLeft = rows.map((r) => r.left).reduce(math.min);
    final maxRight = rows.map((r) => r.right).reduce(math.max);
    final width = math.max(1.0, maxRight - minLeft);
    final mid = (minLeft + maxRight) / 2;
    final pageMid = layout.width / 2;

    final blocks = <DocBlock>[];
    final buf = StringBuffer();
    var type = BlockType.paragraph;
    var align = BlockAlign.left;
    var level = 1;
    var heights = <double>[];
    var top = 0.0, left = double.infinity, right = 0.0, bottom = 0.0;
    int? fill, color;
    LayoutRow? prev;

    void flush() {
      final t = buf.toString().trim();
      if (t.isNotEmpty) {
        heights.sort();
        final hpx = heights.isEmpty ? h : heights[heights.length ~/ 2];
        final pt = pxToPt <= 0 ? 0.0 : (hpx * pxToPt / 1.25).clamp(6.0, 28.0);
        blocks.add(DocBlock(
          t,
          type: type,
          level: level,
          align: align,
          fontPt: pt.toDouble(),
          bold: type == BlockType.heading || fill != null,
          fill: fill,
          fontColor: color,
          top: top,
          left: left,
          right: right,
          bottom: bottom,
        ));
      }
      buf.clear();
      heights = [];
      left = double.infinity;
      right = 0;
    }

    for (final r in rows) {
      var text = r.text.trim();
      if (text.isEmpty) continue;

      final rowMid = (r.left + r.right) / 2;
      final centered = ((r.left - minLeft) > width * 0.1 &&
              (maxRight - r.right) > width * 0.1 &&
              (rowMid - mid).abs() < width * 0.05) ||
          ((rowMid - pageMid).abs() < layout.width * 0.04 &&
              (r.right - r.left) < layout.width * 0.8 &&
              r.left > layout.width * 0.12);
      final rightAligned = !centered &&
          (maxRight - r.right) < width * 0.02 &&
          (r.left - minLeft) > width * 0.4;
      final rowAlign = centered
          ? BlockAlign.center
          : rightAligned
              ? BlockAlign.right
              : BlockAlign.left;

      final style = styleAt?.call(r);
      final isHeading = r.height > h * 1.6 ||
          (centered &&
              text.length <= 100 &&
              text == text.toUpperCase() &&
              text.contains(_upper));
      final isBullet = _bullet.hasMatch(text);
      final isNumbered = _numbered.hasMatch(text);

      final p = prev;
      final continues = p != null &&
          buf.isNotEmpty &&
          type != BlockType.heading &&
          !isHeading &&
          !isBullet &&
          !isNumbered &&
          style?.fill == fill &&
          rowAlign == BlockAlign.left &&
          align == BlockAlign.left &&
          (r.top - p.bottom) < h * 0.9 &&
          p.right >= maxRight - width * 0.12 &&
          (r.left - p.left) < h * 1.5;

      if (continues) {
        buf.write(' $text');
      } else {
        flush();
        if (isBullet) {
          text = text.replaceFirst(_bullet, '');
          type = BlockType.bullet;
        } else if (isNumbered) {
          type = BlockType.numbered;
        } else if (isHeading) {
          type = BlockType.heading;
          level = r.height > h * 1.8 ? 1 : (r.height > h * 1.5 ? 2 : 3);
        } else {
          type = BlockType.paragraph;
        }
        align = rowAlign;
        fill = style?.fill;
        color = style?.color;
        top = r.top;
        buf.write(text);
      }
      heights.add(r.height);
      left = math.min(left, r.left);
      right = math.max(right, r.right);
      bottom = r.bottom;
      prev = r;
    }
    flush();
    return blocks;
  }
}
