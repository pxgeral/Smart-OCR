import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/raster.dart';

/// Ruas garis lurus (boleh sedikit miring) pada gambar kerja.
class GridLine {
  GridLine(this.pos, this.s, this.e, this.slope, this.mid);

  /// Posisi tegak lurus garis (y untuk garis horizontal, x untuk vertikal)
  /// pada koordinat [mid] di sepanjang garis.
  final double pos;
  final int s, e;
  final double slope, mid;

  double at(double t) => pos + slope * (t - mid);
  int get length => e - s;
}

/// Kumpulan garis paralel yang menjadi satu batas grid.
class GridBoundary {
  GridBoundary(this.lines, this.ref) {
    var ws = 0.0, p = 0.0, sl = 0.0;
    for (final l in lines) {
      final w = math.max(1, l.length).toDouble();
      ws += w;
      p += w * l.at(ref);
      sl += w * l.slope;
    }
    pos = p / ws;
    slope = sl / ws;
  }

  final List<GridLine> lines;
  final double ref;
  late final double pos, slope;

  double at(double t) => pos + slope * (t - ref);
}

/// Sel hasil deteksi (indeks grid dasar + rentang gabungan).
class DetectedCell {
  DetectedCell(this.row, this.col, this.rowSpan, this.colSpan);
  final int row, col, rowSpan, colSpan;

  /// Kotak pada gambar kerja: left, top, right, bottom.
  List<double> box = const [0, 0, 0, 0];
  int fill = 0xFFFFFF;
}

class DetectedTable {
  DetectedTable(this.xs, this.ys, this.cells);
  final List<GridBoundary> xs, ys;
  final List<DetectedCell> cells;

  int get rowCount => ys.length - 1;
  int get colCount => xs.length - 1;

  double get left => xs.first.pos;
  double get right => xs.last.pos;
  double get top => ys.first.pos;
  double get bottom => ys.last.pos;

  (double, double) corner(int c, int r) {
    var y = ys[r].pos;
    var x = xs[c].at(y);
    for (var i = 0; i < 3; i++) {
      x = xs[c].at(y);
      y = ys[r].at(x);
    }
    return (x, y);
  }

  List<double> boxOf(int r, int c, int rs, int cs) {
    var x0 = double.infinity, y0 = double.infinity;
    var x1 = double.negativeInfinity, y1 = double.negativeInfinity;
    for (final cc in [c, c + cs]) {
      for (final rr in [r, r + rs]) {
        final (x, y) = corner(cc, rr);
        x0 = math.min(x0, x);
        y0 = math.min(y0, y);
        x1 = math.max(x1, x);
        y1 = math.max(y1, y);
      }
    }
    return [x0, y0, x1, y1];
  }
}

/// Deteksi struktur tabel bergaris dari gambar:
/// garis tipis gelap/terang dan tepi warna -> ruas garis -> grid ->
/// sel gabungan (rowspan/colspan) + warna latar sel.
///
/// Dipindahkan dari prototipe dan diuji pada scan formulir CamScanner.
class TableStructureDetector {
  TableStructureDetector(this.image) : unit = math.max(image.width, image.height) / 1600;

  final Raster image;
  final double unit;
  late Uint8List _hm, _vm;

  int get _w => image.width;
  int get _h => image.height;

  List<DetectedTable> detect() {
    if (_w < 200 || _h < 200) return const [];
    _buildMasks();
    var hs = _chain(_runs(_hm, true, (28 * unit).round()));
    var vs = _chain(_runs(_vm, false, (20 * unit).round()));
    final tol = 7 * unit;
    for (var i = 0; i < 2; i++) {
      final vs2 = [
        for (final v in vs)
          if (v.length > _h * 0.25 ||
              (_touches(v, v.s.toDouble(), hs, tol) &&
                  _touches(v, v.e.toDouble(), hs, tol)))
            v
      ];
      final hs2 = [
        for (final h in hs)
          if (h.length > _w * 0.25 ||
              (_touches(h, h.s.toDouble(), vs, tol) &&
                  _touches(h, h.e.toDouble(), vs, tol)))
            h
      ];
      vs = vs2;
      hs = hs2;
    }
    return _findTables(hs, vs, tol);
  }

  // ---------------------------------------------------------------- masks

  void _buildMasks() {
    final w = _w, h = _h;
    final l = image.lum;
    final px = image.rgb;
    final hm = Uint8List(w * h);
    final vm = Uint8List(w * h);
    const t = 40, te = 50, tu = 18;

    bool ridge(int i, int step) {
      final c = l[i];
      for (var k = 2; k <= 4; k++) {
        final a = l[i - k * step], b = l[i + k * step];
        final d1 = a - c, d2 = b - c;
        if (math.min(d1, d2) > t || math.min(-d1, -d2) > t) return true;
      }
      return false;
    }

    bool edge(int i, int step) {
      for (var ch = 0; ch < 3; ch++) {
        final a = px[(i - 2 * step) * 3 + ch];
        final b = px[(i + 2 * step) * 3 + ch];
        if ((a - b).abs() <= te) continue;
        final a2 = px[(i - 6 * step) * 3 + ch];
        final b2 = px[(i + 6 * step) * 3 + ch];
        if ((a - a2).abs() < tu && (b - b2).abs() < tu) return true;
      }
      return false;
    }

    for (var y = 6; y < h - 6; y++) {
      final row = y * w;
      for (var x = 6; x < w - 6; x++) {
        final i = row + x;
        if (ridge(i, w) || edge(i, w)) hm[i] = 1;
        if (ridge(i, 1) || edge(i, 1)) vm[i] = 1;
      }
    }
    // toleransi goyang 1 px
    _hm = Uint8List(w * h);
    _vm = Uint8List(w * h);
    for (var y = 1; y < h; y++) {
      for (var x = 1; x < w; x++) {
        final i = y * w + x;
        _hm[i] = hm[i] | hm[i - w];
        _vm[i] = vm[i] | vm[i - 1];
      }
    }
  }

  /// Ruas berurutan (pos, start, end) sepanjang baris (horizontal) atau
  /// kolom (vertikal) mask.
  List<(int, int, int)> _runs(Uint8List m, bool horizontal, int minLen) {
    final gap = math.max(1, unit.round());
    final out = <(int, int, int)>[];
    final outer = horizontal ? _h : _w;
    final inner = horizontal ? _w : _h;
    for (var p = 0; p < outer; p++) {
      var start = -1, last = -10;
      for (var q = 0; q < inner; q++) {
        final on = horizontal ? m[p * _w + q] : m[q * _w + p];
        if (on == 0) continue;
        if (start < 0) {
          start = q;
        } else if (q - last > gap + 1) {
          if (last - start + 1 >= minLen) out.add((p, start, last));
          start = q;
        }
        last = q;
      }
      if (start >= 0 && last - start + 1 >= minLen) out.add((p, start, last));
    }
    return out;
  }

  List<GridLine> _chain(List<(int, int, int)> segs, {int tol = 3, int gap = 12}) {
    final chains = <_Chain>[];
    var active = <_Chain>[];
    for (final (p, s, e) in segs) {
      _Chain? hit;
      for (final c in active) {
        if ((p - c.lastP).abs() <= tol && s <= c.e + gap && e >= c.s - gap) {
          hit = c;
          break;
        }
      }
      if (hit != null) {
        hit.pieces.add((p, s, e));
        hit.s = math.min(hit.s, s);
        hit.e = math.max(hit.e, e);
        hit.lastP = p;
      } else {
        final c = _Chain(p, s, e);
        chains.add(c);
        active.add(c);
      }
      active = [for (final c in active) if (p - c.lastP <= tol + 1) c];
    }
    final out = <GridLine>[];
    for (final c in chains) {
      var ws = 0.0, mm = 0.0, pm = 0.0;
      for (final (pp, ps, pe) in c.pieces) {
        final w = (pe - ps + 1).toDouble();
        ws += w;
        mm += w * (ps + pe) / 2;
        pm += w * pp;
      }
      mm /= ws;
      pm /= ws;
      var slope = 0.0;
      if (c.e - c.s > 60 && c.pieces.length > 1) {
        var nu = 0.0, den = 0.0;
        for (final (pp, ps, pe) in c.pieces) {
          final w = (pe - ps + 1).toDouble();
          final mid = (ps + pe) / 2;
          nu += w * (mid - mm) * (pp - pm);
          den += w * (mid - mm) * (mid - mm);
        }
        if (den > 0) slope = (nu / den).clamp(-0.03, 0.03);
      }
      out.add(GridLine(pm, c.s, c.e, slope, mm));
    }
    return out;
  }

  bool _touches(GridLine line, double t, List<GridLine> others, double tol) {
    final p = line.at(t);
    for (final o in others) {
      if (o.s - tol <= p && p <= o.e + tol && (o.at(p) - t).abs() <= tol) {
        return true;
      }
    }
    return false;
  }

  bool _crosses(GridLine h, GridLine v, double tol) {
    final x = v.at(h.pos);
    final y = h.at(x);
    return h.s - tol <= x && x <= h.e + tol && v.s - tol <= y && y <= v.e + tol;
  }

  // ---------------------------------------------------------------- tables

  List<DetectedTable> _findTables(
      List<GridLine> hs, List<GridLine> vs, double tol) {
    final n = hs.length + vs.length;
    final parent = List<int>.generate(n, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    for (var i = 0; i < hs.length; i++) {
      for (var j = 0; j < vs.length; j++) {
        if (_crosses(hs[i], vs[j], tol)) {
          parent[find(i)] = find(hs.length + j);
        }
      }
    }
    final comps = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      comps.putIfAbsent(find(i), () => []).add(i);
    }
    final cands = <(List<GridLine>, List<GridLine>)>[];
    for (final idx in comps.values) {
      final ch = [for (final i in idx) if (i < hs.length) hs[i]];
      final cv = [for (final i in idx) if (i >= hs.length) vs[i - hs.length]];
      if (ch.length >= 2 && cv.length >= 2) cands.add((ch, cv));
    }
    double hLen(List<GridLine> l) => l.fold(0.0, (a, b) => a + b.length);
    cands.sort((a, b) => hLen(b.$1).compareTo(hLen(a.$1)));

    final used = <GridLine>{};
    final out = <DetectedTable>[];
    for (final cand in cands) {
      if (cand.$1.any(used.contains) || cand.$2.any(used.contains)) continue;
      final ch = [...cand.$1];
      final cv = [...cand.$2];
      for (var iter = 0; iter < 3; iter++) {
        final x0 = math.min(ch.map((h) => h.s.toDouble()).reduce(math.min),
            cv.map((v) => v.pos).reduce(math.min));
        final x1 = math.max(ch.map((h) => h.e.toDouble()).reduce(math.max),
            cv.map((v) => v.pos).reduce(math.max));
        final y0 = math.min(cv.map((v) => v.s.toDouble()).reduce(math.min),
            ch.map((h) => h.pos).reduce(math.min));
        final y1 = math.max(cv.map((v) => v.e.toDouble()).reduce(math.max),
            ch.map((h) => h.pos).reduce(math.max));
        final near = 40 * unit;
        var grew = false;
        for (final h in hs) {
          if (used.contains(h) || ch.contains(h)) continue;
          final ov = math.min(h.e.toDouble(), x1) - math.max(h.s.toDouble(), x0);
          if (ov > 0.5 * (x1 - x0) && y0 - near <= h.pos && h.pos <= y1 + near) {
            ch.add(h);
            grew = true;
          }
        }
        for (final v in vs) {
          if (used.contains(v) || cv.contains(v)) continue;
          final ov = math.min(v.e.toDouble(), y1) - math.max(v.s.toDouble(), y0);
          if (ov > 0.5 * math.min(v.length.toDouble(), y1 - y0) &&
              x0 - tol <= v.pos &&
              v.pos <= x1 + tol) {
            cv.add(v);
            grew = true;
          }
        }
        if (!grew) break;
      }
      used
        ..addAll(ch)
        ..addAll(cv);
      final t = _makeGrid(ch, cv, tol);
      if (t != null) out.add(t);
    }
    out.sort((a, b) => a.top.compareTo(b.top));
    return out;
  }

  List<GridBoundary> _cluster(List<GridLine> lines, double ref, double tol) {
    final sorted = [...lines]..sort((a, b) => a.at(ref).compareTo(b.at(ref)));
    final groups = <List<GridLine>>[];
    for (final l in sorted) {
      if (groups.isNotEmpty && l.at(ref) - groups.last.last.at(ref) <= tol) {
        groups.last.add(l);
      } else {
        groups.add([l]);
      }
    }
    return [for (final g in groups) GridBoundary(g, ref)];
  }

  double _coverage(GridBoundary b, double a0, double a1, double tol) {
    final iv = <(double, double)>[];
    for (final l in b.lines) {
      final s = math.max(l.s.toDouble(), a0), e = math.min(l.e.toDouble(), a1);
      if (e > s && (l.at((s + e) / 2) - b.at((s + e) / 2)).abs() <= tol) {
        iv.add((s, e));
      }
    }
    iv.sort((a, b) => a.$1.compareTo(b.$1));
    var cov = 0.0, cur = a0;
    for (final (s, e) in iv) {
      if (e <= cur) continue;
      cov += e - math.max(s, cur);
      cur = e;
    }
    return cov / math.max(1.0, a1 - a0);
  }

  static double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    return s[s.length ~/ 2];
  }

  static List<double> _diffs(List<GridBoundary> b) =>
      [for (var i = 1; i < b.length; i++) b[i].pos - b[i - 1].pos];

  DetectedTable? _makeGrid(List<GridLine> ch, List<GridLine> cv, double tol) {
    final xr = (ch.map((h) => h.s).reduce(math.min) +
            ch.map((h) => h.e).reduce(math.max)) /
        2;
    final yr = (cv.map((v) => v.s).reduce(math.min) +
            cv.map((v) => v.e).reduce(math.max)) /
        2;
    var ys = _cluster(ch, xr, tol);
    var xs = _cluster(cv, yr, tol);

    // bingkai luar implisit dari ujung-ujung garis
    final lefts = ch.map((h) => h.s.toDouble()).toList()..sort();
    final rights = ch.map((h) => h.e.toDouble()).toList()..sort();
    final tops = cv.map((v) => v.s.toDouble()).toList()..sort();
    final bots = cv.map((v) => v.e.toDouble()).toList()..sort();
    final lx = lefts[lefts.length ~/ 2], rx = rights[rights.length ~/ 2];
    final ty = tops.first, by = bots.last;
    GridBoundary synth(double pos, double s, double e, double ref) =>
        GridBoundary([GridLine(pos, s.round(), e.round(), 0, ref)], ref);
    if (lx < xs.first.pos - 12 * unit) xs.insert(0, synth(lx, ty, by, yr));
    if (rx > xs.last.pos + 12 * unit) xs.add(synth(rx, ty, by, yr));
    if (ty < ys.first.pos - 10 * unit) ys.insert(0, synth(ty, lx, rx, xr));
    if (by > ys.last.pos + 10 * unit) ys.add(synth(by, lx, rx, xr));

    for (var iter = 0; iter < 2; iter++) {
      if (xs.length < 2 || ys.length < 2) return null;
      final tw = xs.last.pos - xs.first.pos, th = ys.last.pos - ys.first.pos;
      final mh = _median(_diffs(ys)), mw = _median(_diffs(xs));
      final ys0 = ys, xs0 = xs;
      xs = [
        for (var i = 0; i < xs0.length; i++)
          if (i == 0 ||
              i == xs0.length - 1 ||
              _coverage(xs0[i], ys0.first.pos, ys0.last.pos, tol) * th >=
                  math.min(0.3 * th, 4 * mh))
            xs0[i]
      ];
      ys = [
        for (var i = 0; i < ys0.length; i++)
          if (i == 0 ||
              i == ys0.length - 1 ||
              _coverage(ys0[i], xs.first.pos, xs.last.pos, tol) * tw >=
                  math.min(0.3 * tw, 4 * mw))
            ys0[i]
      ];
    }
    xs = _dedup(xs, ys, 12 * unit, tol);
    ys = _dedup(ys, xs, 10 * unit, tol);
    if (xs.length < 2 || ys.length < 2) return null;
    if (xs.length > 80 || ys.length > 400) return null;
    final table = _buildCells(xs, ys, tol);
    // tabel 1x1 kecil (kotak isian / bingkai) tetap dipakai hanya bila besar
    if (table.cells.length == 1 &&
        (table.right - table.left) * (table.bottom - table.top) <
            0.02 * _w * _h) {
      return null;
    }
    return table;
  }

  List<GridBoundary> _dedup(
      List<GridBoundary> bs, List<GridBoundary> other, double minD, double tol) {
    final out = [...bs];
    var i = 1;
    while (i < out.length) {
      if (out[i].pos - out[i - 1].pos >= minD) {
        i++;
        continue;
      }
      if (i - 1 == 0) {
        out.removeAt(i);
      } else if (i == out.length - 1) {
        out.removeAt(i - 1);
      } else {
        final ca = _coverage(out[i - 1], other.first.pos, other.last.pos, tol);
        final cb = _coverage(out[i], other.first.pos, other.last.pos, tol);
        out.removeAt(cb > ca ? i - 1 : i);
      }
    }
    return out;
  }

  /// Fraksi terbaik (atas semua offset konstan) titik di [a0,a1] yang
  /// memiliki piksel mask pada b.at(t)+d (+-1 px).
  double _maskCov(Uint8List mask, GridBoundary b, double a0, double a1,
      double tol, bool vertical, {double trim = 0}) {
    final span = a1 - a0;
    final s = (a0 + 2 + span * trim).ceil();
    final e = (a1 - 2 - span * trim).floor();
    if (e <= s) return 1;
    final tl = tol.round();
    final counts = List<int>.filled(2 * tl + 1, 0);
    final n = e - s + 1;
    final len = vertical ? _w : _h;
    for (var t = s; t <= e; t++) {
      if (vertical ? (t < 0 || t >= _h) : (t < 0 || t >= _w)) continue;
      final p = b.at(t.toDouble()).round();
      for (var k = 0; k <= 2 * tl; k++) {
        final q = p + k - tl;
        if (q < 1 || q >= len - 1) continue;
        final hit = vertical
            ? (mask[t * _w + q] | mask[t * _w + q - 1] | mask[t * _w + q + 1])
            : (mask[q * _w + t] | mask[(q - 1) * _w + t] | mask[(q + 1) * _w + t]);
        if (hit != 0) counts[k]++;
      }
    }
    return counts.reduce(math.max) / n;
  }

  DetectedTable _buildCells(
      List<GridBoundary> xs, List<GridBoundary> ys, double tol) {
    final rows = ys.length - 1, cols = xs.length - 1;
    final tmp = DetectedTable(xs, ys, const []);
    final medH = _median(_diffs(ys));
    final t2 = math.max(3.0, tol * 0.6);

    final base = List.generate(rows, (r) => List.generate(cols, (c) {
          final b = tmp.boxOf(r, c, 1, 1);
          return image.backgroundColor(b[0], b[1], b[2], b[3]);
        }));

    bool sameFill(int a, int b) => isFillColor(a) && colorDistance(a, b) < 30;

    final vb = List.generate(
        rows,
        (r) => List.generate(math.max(0, cols - 1), (c) {
              final b = xs[c + 1];
              final y0 = ys[r].at(b.pos), y1 = ys[r + 1].at(b.pos);
              var need = y1 - y0 >= 30 * unit ? 0.6 : 0.85;
              if (y1 - y0 < 0.8 * medH && sameFill(base[r][c], base[r][c + 1])) {
                need = 0.97;
              }
              return _maskCov(_vm, b, y0, y1, t2, true) > need;
            }));
    final hb = List.generate(
        math.max(0, rows - 1),
        (r) => List.generate(cols, (c) {
              final b = ys[r + 1];
              return _maskCov(_hm, b, xs[c].at(b.pos), xs[c + 1].at(b.pos), t2,
                      false,
                      trim: 0.15) >
                  0.6;
            }));

    final taken = List.generate(rows, (_) => List.filled(cols, false));
    final cells = <DetectedCell>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (taken[r][c]) continue;
        var c1 = c;
        while (c1 + 1 < cols && !vb[r][c1] && !taken[r][c1 + 1]) {
          c1++;
        }
        var r1 = r;
        while (r1 + 1 < rows) {
          var ok = true;
          for (var k = c; k <= c1 && ok; k++) {
            if (hb[r1][k] || taken[r1 + 1][k]) ok = false;
          }
          for (var k = c; k < c1 && ok; k++) {
            if (vb[r1 + 1][k]) ok = false;
          }
          if (ok && c1 + 1 < cols && !vb[r1 + 1][c1]) ok = false;
          if (ok && c > 0 && !vb[r1 + 1][c - 1]) ok = false;
          if (!ok) break;
          r1++;
        }
        for (var rr = r; rr <= r1; rr++) {
          for (var cc = c; cc <= c1; cc++) {
            taken[rr][cc] = true;
          }
        }
        cells.add(DetectedCell(r, c, r1 - r + 1, c1 - c + 1));
      }
    }
    final table = DetectedTable(xs, ys, cells);
    for (final cell in cells) {
      cell.box = table.boxOf(cell.row, cell.col, cell.rowSpan, cell.colSpan);
      cell.fill = cell.rowSpan == 1 && cell.colSpan == 1
          ? base[cell.row][cell.col]
          : image.backgroundColor(
              cell.box[0], cell.box[1], cell.box[2], cell.box[3]);
    }
    return table;
  }
}

class _Chain {
  _Chain(int p, this.s, this.e)
      : lastP = p,
        pieces = [(p, s, e)];
  final List<(int, int, int)> pieces;
  int s, e, lastP;
}
