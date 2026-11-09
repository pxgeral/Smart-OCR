import 'dart:math' as math;

import '../../models/table_data.dart';
import 'layout_analyzer.dart';

abstract final class TableDetector {
  static final _digit = RegExp(r'\d');
  static final _numeric = RegExp(r'^[\d\s.,%+\-/]+$');

  /// Null bila halaman bukan tabel (kecuali [force]).
  /// Tabel = minimal 3 baris bersel >= 2 dan jumlahnya >= 50% semua baris.
  static TableData? detect(PageLayout layout, {bool force = false}) {
    final rows = layout.rows;
    if (rows.isEmpty) return null;

    final multi = rows.where((r) => r.cells.length >= 2).toList();
    final looksLikeTable =
        multi.length >= 3 && multi.length >= rows.length * 0.5;
    if (!looksLikeTable && !force) return null;
    if (multi.isEmpty) {
      return TableData(rows: [for (final r in rows) [r.text]], hasHeader: false);
    }

    // Jumlah kolom = jumlah sel yang paling sering muncul pada satu baris.
    final freq = <int, int>{};
    for (final r in multi) {
      freq[r.cells.length] = (freq[r.cells.length] ?? 0) + 1;
    }
    var n = 2;
    var best = 0;
    freq.forEach((k, v) {
      if (v > best || (v == best && k > n)) {
        best = v;
        n = k;
      }
    });

    // Batas kolom = gabungan rentang-x sel ke-j dari baris berjumlah n sel.
    final base = multi.where((r) => r.cells.length == n).toList();
    final lo = [
      for (var j = 0; j < n; j++)
        base.map((r) => r.cells[j].left).reduce(math.min),
    ];
    final hi = [
      for (var j = 0; j < n; j++)
        base.map((r) => r.cells[j].right).reduce(math.max),
    ];

    final out = <List<String>>[];
    for (final r in rows) {
      final line = List<String>.filled(n, '');
      for (final c in r.cells) {
        final j = _column(c, lo, hi);
        line[j] = line[j].isEmpty ? c.text : '${line[j]} ${c.text}';
      }
      out.add(line);
    }
    return TableData(rows: out, hasHeader: _looksLikeHeader(out.first));
  }

  /// Kolom dengan tumpang-tindih terbesar (atau terdekat bila tak ada).
  static int _column(LayoutCell c, List<double> lo, List<double> hi) {
    var best = 0;
    var bestOverlap = double.negativeInfinity;
    for (var j = 0; j < lo.length; j++) {
      final overlap = math.min(c.right, hi[j]) - math.max(c.left, lo[j]);
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        best = j;
      }
    }
    return best;
  }

  static bool _looksLikeHeader(List<String> row) {
    final filled = row.where((c) => c.isNotEmpty).toList();
    return filled.length >= 2 &&
        filled.every((c) => !(_numeric.hasMatch(c) && _digit.hasMatch(c)));
  }
}
