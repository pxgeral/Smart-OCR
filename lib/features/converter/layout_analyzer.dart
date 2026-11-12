import 'dart:math' as math;

import '../../models/ocr_result.dart';

class LayoutCell {
  const LayoutCell(this.text, this.left, this.right);
  final String text;
  final double left, right;
}

class LayoutRow {
  const LayoutRow(this.cells, this.top, this.bottom);
  final List<LayoutCell> cells;
  final double top, bottom;

  double get height => bottom - top;
  double get left => cells.first.left;
  double get right => cells.last.right;
  String get text => cells.map((c) => c.text).join(' ');
}

class PageLayout {
  const PageLayout(this.rows, this.lineHeight, this.width);
  final List<LayoutRow> rows;
  final double lineHeight, width;
}

/// Kata (OcrBox) -> baris -> sel. Dipakai bersama oleh deteksi tabel
/// dan pembangun dokumen.
///
/// [cellGap]: kata dipisah menjadi sel baru bila jarak horizontalnya
/// lebih dari cellGap x tinggi kata median. double.infinity = 1 sel per baris.
abstract final class LayoutAnalyzer {
  static PageLayout analyze(OcrPage page, {double cellGap = 1.0}) {
    if (page.boxes.isEmpty) return PageLayout(const [], 0, page.width);

    final boxes = [...page.boxes]
      ..sort((a, b) => a.centerY.compareTo(b.centerY));
    final hs = boxes.map((b) => b.height).toList()..sort();
    final med = hs[hs.length ~/ 2];

    // 1) kelompokkan kata ke baris menurut posisi vertikal
    final groups = <List<OcrBox>>[];
    for (final b in boxes) {
      if (groups.isNotEmpty) {
        final g = groups.last;
        final cy = g.fold<double>(0, (s, x) => s + x.centerY) / g.length;
        if ((b.centerY - cy).abs() <= med * 0.6) {
          g.add(b);
          continue;
        }
      }
      groups.add([b]);
    }

    // 2) dalam tiap baris, pecah menjadi sel menurut jarak horizontal
    final rows = <LayoutRow>[];
    for (final g in groups) {
      g.sort((a, b) => a.left.compareTo(b.left));
      final cells = <LayoutCell>[];
      var text = g.first.text;
      var l = g.first.left;
      var r = g.first.right;
      for (final b in g.skip(1)) {
        if (b.left - r > med * cellGap) {
          cells.add(LayoutCell(text, l, r));
          text = b.text;
          l = b.left;
          r = b.right;
        } else {
          text = '$text ${b.text}';
          r = math.max(r, b.right);
        }
      }
      cells.add(LayoutCell(text, l, r));
      rows.add(LayoutRow(
        cells,
        g.map((b) => b.top).reduce(math.min),
        g.map((b) => b.bottom).reduce(math.max),
      ));
    }
    return PageLayout(rows, med, page.width);
  }
}
