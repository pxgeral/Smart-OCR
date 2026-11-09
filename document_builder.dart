import 'dart:math' as math;

import '../../models/converted_content.dart';
import 'layout_analyzer.dart';

/// Baris OCR -> paragraf, heading, bullet, nomor, dan alignment.
abstract final class DocumentBuilder {
  static final _bullet = RegExp(r'^[\-•·●○\*>]\s+');
  static final _numbered = RegExp(r'^\(?\d{1,3}[.)]\s+');
  static final _upper = RegExp(r'[A-Z]');

  static List<DocBlock> build(PageLayout layout) {
    final rows = layout.rows;
    if (rows.isEmpty) return const [];

    final h = layout.lineHeight;
    final minLeft = rows.map((r) => r.left).reduce(math.min);
    final maxRight = rows.map((r) => r.right).reduce(math.max);
    final width = math.max(1.0, maxRight - minLeft);
    final mid = (minLeft + maxRight) / 2;

    final blocks = <DocBlock>[];
    final buf = StringBuffer();
    var type = BlockType.paragraph;
    var align = BlockAlign.left;
    var level = 1;
    LayoutRow? prev;

    void flush() {
      final t = buf.toString().trim();
      if (t.isNotEmpty) {
        blocks.add(DocBlock(t, type: type, level: level, align: align));
      }
      buf.clear();
    }

    for (final r in rows) {
      var text = r.text.trim();
      if (text.isEmpty) continue;

      final centered = (r.left - minLeft) > width * 0.1 &&
          (maxRight - r.right) > width * 0.1 &&
          (((r.left + r.right) / 2) - mid).abs() < width * 0.05;
      final rightAligned = !centered &&
          (maxRight - r.right) < width * 0.02 &&
          (r.left - minLeft) > width * 0.4;
      final rowAlign = centered
          ? BlockAlign.center
          : rightAligned
              ? BlockAlign.right
              : BlockAlign.left;

      final isHeading = r.height > h * 1.35 ||
          (centered &&
              text.length <= 80 &&
              text == text.toUpperCase() &&
              text.contains(_upper));
      final isBullet = _bullet.hasMatch(text);
      final isNumbered = _numbered.hasMatch(text);

      // Baris lanjutan paragraf: baris sebelumnya penuh sampai tepi kanan,
      // jarak vertikal kecil, tanpa indentasi baru.
      final p = prev;
      final continues = p != null &&
          buf.isNotEmpty &&
          type != BlockType.heading &&
          !isHeading &&
          !isBullet &&
          !isNumbered &&
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
        buf.write(text);
      }
      prev = r;
    }
    flush();
    return blocks;
  }
}
