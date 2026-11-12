import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../core/constants.dart';
import '../../core/raster.dart';
import '../../models/table_data.dart';
import 'table_structure.dart';

/// Sel terdeteksi pada gambar resolusi penuh.
class CellInfo {
  CellInfo({
    required this.row,
    required this.col,
    required this.rowSpan,
    required this.colSpan,
    required this.box,
    required this.fill,
    required this.hasInk,
    required this.ink,
    required this.align,
    required this.inkHeight,
    this.checkbox = 0,
  });

  final int row, col, rowSpan, colSpan;
  final List<double> box; // full-res px
  final int fill;
  final bool hasInk;
  final int? ink; // warna tinta bila berwarna (mis. pulpen biru)
  final CellAlign align;
  final double inkHeight; // full-res px

  /// 0 = bukan kotak centang, 1 = kotak kosong, 2 = kotak dicentang;
  /// negatif = ditebak dari banyaknya tinta (perlu dicek).
  final int checkbox;
  int slot = -1; // indeks MosaicSlot untuk OCR per sel
}

class TableInfo {
  TableInfo({
    required this.colWidths,
    required this.rowHeights,
    required this.left,
    required this.top,
    required this.cells,
  });
  final List<double> colWidths, rowHeights;
  final double left, top;
  final List<CellInfo> cells;

  double get right => left + colWidths.fold(0.0, (a, b) => a + b);
  double get bottom => top + rowHeights.fold(0.0, (a, b) => a + b);
}

/// Posisi potongan sel di dalam gambar mosaik (untuk memetakan balik
/// hasil OCR ke sel).
class MosaicSlot {
  MosaicSlot(this.table, this.cell, this.mosaic, this.x, this.y, this.w, this.h);
  final int table, cell, mosaic;
  final double x, y, w, h;
}

/// Pita/judul berwarna di luar tabel (mis. "I. TABEL PEMANTAUAN ...").
class BandInfo {
  BandInfo(this.left, this.top, this.right, this.bottom, this.fill);
  final double left, top, right, bottom;
  final int fill;
}

class PageAnalysis {
  PageAnalysis({
    required this.imagePath,
    required this.width,
    required this.height,
    required this.tables,
    required this.bands,
    required this.slots,
    required this.mosaicA,
    required this.mosaicB,
  });

  final String imagePath; // gambar ternormalisasi (orientasi benar, JPEG)
  final int width, height;
  final List<TableInfo> tables;
  final List<BandInfo> bands;
  final List<MosaicSlot> slots;
  final List<String> mosaicA, mosaicB; // warna asli & kontras dinormalisasi
}

/// Tahap 1 (berjalan di Isolate): normalisasi gambar, deteksi struktur tabel,
/// warna, keberadaan tinta, dan pembuatan mosaik potongan sel untuk OCR ulang.
abstract final class PageAnalyzer {
  static const workSide = 1600;

  static PageAnalysis analyze({
    required String sourcePath,
    required String workDir,
    required int pageIndex,
    required bool detectTables,
    required bool cellOcr,
  }) {
    final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
    if (decoded == null) {
      throw StateError('Gambar tidak bisa dibaca: $sourcePath');
    }
    var full = img.bakeOrientation(decoded);
    final maxSide = math.max(full.width, full.height);
    if (maxSide > AppConstants.maxImageSide) {
      final s = AppConstants.maxImageSide / maxSide;
      full = img.copyResize(full,
          width: (full.width * s).round(),
          height: (full.height * s).round(),
          interpolation: img.Interpolation.average);
    }
    if (full.numChannels != 3) full = full.convert(numChannels: 3);
    final normPath = '$workDir/page_${pageIndex + 1}.jpg';

    if (!detectTables) {
      File(normPath).writeAsBytesSync(
          img.encodeJpg(full, quality: AppConstants.jpegQuality));
      return PageAnalysis(
        imagePath: normPath,
        width: full.width,
        height: full.height,
        tables: const [],
        bands: const [],
        slots: const [],
        mosaicA: const [],
        mosaicB: const [],
      );
    }

    var (raster, scale) = _work(full);
    var detected = TableStructureDetector(raster).detect();

    // Foto miring/perspektif: luruskan tabel terbesar lalu deteksi ulang,
    // agar garis kolom tegak dan teks tidak tertukar antarkolom.
    if (detected.isNotEmpty) {
      final quad = _quad(detected);
      if (quad != null && _needsRectify(quad, raster)) {
        final warped = _rectify(full, [for (final v in quad) v * scale]);
        if (warped != null) {
          final (r2, s2) = _work(warped);
          final again = TableStructureDetector(r2).detect();
          // pakai hasil pelurusan hanya bila strukturnya tidak memburuk
          if (again.isNotEmpty && _score(again) >= _score(detected) * 0.95) {
            full = warped;
            raster = r2;
            scale = s2;
            detected = again;
          }
        }
      }
    }
    File(normPath).writeAsBytesSync(
        img.encodeJpg(full, quality: AppConstants.jpegQuality));

    final tables = <TableInfo>[
      for (final t in detected) _toInfo(t, raster, scale),
    ];
    final paper = tables.isEmpty ? 0xFFFFFF : _paperOf(detected.first);
    final bands = _bands(raster, detected, scale, paper);

    final slots = <MosaicSlot>[];
    final mosaicA = <String>[], mosaicB = <String>[];
    if (cellOcr && tables.isNotEmpty) {
      _buildMosaics(full, tables, workDir, pageIndex, slots, mosaicA, mosaicB);
    }
    return PageAnalysis(
      imagePath: normPath,
      width: full.width,
      height: full.height,
      tables: tables,
      bands: bands,
      slots: slots,
      mosaicA: mosaicA,
      mosaicB: mosaicB,
    );
  }

  static (Raster, double) _work(img.Image full) {
    final ws = math.min(1.0, workSide / math.max(full.width, full.height));
    final work = ws < 1
        ? img.copyResize(full,
            width: (full.width * ws).round(),
            height: (full.height * ws).round(),
            interpolation: img.Interpolation.linear)
        : full;
    return (Raster.fromImage(work), full.width / work.width);
  }

  // ---------------------------------------------------- perspektif

  /// Empat pojok tabel terbesar (kiri-atas, kanan-atas, kanan-bawah,
  /// kiri-bawah) di koordinat gambar kerja: [x0,y0,x1,y1,x2,y2,x3,y3].
  static List<double>? _quad(List<DetectedTable> tables) {
    DetectedTable? best;
    var area = 0.0;
    for (final t in tables) {
      final a = (t.right - t.left) * (t.bottom - t.top);
      if (a > area && t.colCount >= 2 && t.rowCount >= 3) {
        area = a;
        best = t;
      }
    }
    final t = best;
    if (t == null) return null;
    final (ax, ay) = t.corner(0, 0);
    final (bx, by) = t.corner(t.colCount, 0);
    final (cx, cy) = t.corner(t.colCount, t.rowCount);
    final (dx, dy) = t.corner(0, t.rowCount);
    return [ax, ay, bx, by, cx, cy, dx, dy];
  }

  /// Mutu struktur: jumlah sel tunggal (bukan gabungan) di semua tabel.
  static int _score(List<DetectedTable> ts) => ts.fold(
      0, (n, t) => n + t.cells.where((c) => c.rowSpan == 1 && c.colSpan == 1).length);

  static bool _needsRectify(List<double> q, Raster r) {
    final unit = math.max(r.width, r.height) / 1600;
    final dev = [
      (q[0] - q[6]).abs(), // kiri: x atas vs bawah
      (q[2] - q[4]).abs(), // kanan
      (q[1] - q[3]).abs(), // atas: y kiri vs kanan
      (q[7] - q[5]).abs(), // bawah
    ].reduce(math.max);
    final w = q[2] - q[0], h = q[7] - q[1];
    return dev > 3 * unit && w > r.width * 0.25 && h > r.height * 0.15;
  }

  /// Homografi titik tujuan -> sumber (8 parameter, h33 = 1).
  static List<double>? _homography(List<double> dst, List<double> src) {
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final x = dst[i * 2], y = dst[i * 2 + 1];
      final u = src[i * 2], v = src[i * 2 + 1];
      a[i * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
      a[i * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
    }
    // eliminasi Gauss dengan pivot
    for (var c = 0; c < 8; c++) {
      var p = c;
      for (var r = c + 1; r < 8; r++) {
        if (a[r][c].abs() > a[p][c].abs()) p = r;
      }
      if (a[p][c].abs() < 1e-9) return null;
      final tmp = a[c];
      a[c] = a[p];
      a[p] = tmp;
      for (var r = 0; r < 8; r++) {
        if (r == c) continue;
        final f = a[r][c] / a[c][c];
        for (var k = c; k < 9; k++) {
          a[r][k] -= f * a[c][k];
        }
      }
    }
    return [for (var i = 0; i < 8; i++) a[i][8] / a[i][i]];
  }

  /// Luruskan gambar sehingga segiempat [q] (full-res) menjadi persegi panjang.
  static img.Image? _rectify(img.Image full, List<double> q) {
    double dist(int i, int j) => math.sqrt(math.pow(q[i * 2] - q[j * 2], 2) + math.pow(q[i * 2 + 1] - q[j * 2 + 1], 2));
    final w = (dist(0, 1) + dist(3, 2)) / 2;
    final h = (dist(0, 3) + dist(1, 2)) / 2;
    final x0 = (q[0] + q[6]) / 2, y0 = (q[1] + q[3]) / 2;
    final dst = [x0, y0, x0 + w, y0, x0 + w, y0 + h, x0, y0 + h];
    final hm = _homography(dst, q);
    if (hm == null) return null;
    final sw = full.width, sh = full.height;
    final src = full.getBytes(order: img.ChannelOrder.rgb);
    final out = Uint8List(sw * sh * 3);
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        final d = hm[6] * x + hm[7] * y + 1;
        final u = (hm[0] * x + hm[1] * y + hm[2]) / d;
        final v = (hm[3] * x + hm[4] * y + hm[5]) / d;
        final o = (y * sw + x) * 3;
        if (u < 0 || v < 0 || u >= sw - 1 || v >= sh - 1) {
          out[o] = out[o + 1] = out[o + 2] = 255;
          continue;
        }
        final ix = u.floor(), iy = v.floor();
        final fx = u - ix, fy = v - iy;
        final i00 = (iy * sw + ix) * 3, i10 = i00 + 3;
        final i01 = i00 + sw * 3, i11 = i01 + 3;
        for (var ch = 0; ch < 3; ch++) {
          final top = src[i00 + ch] + (src[i10 + ch] - src[i00 + ch]) * fx;
          final bot = src[i01 + ch] + (src[i11 + ch] - src[i01 + ch]) * fx;
          out[o + ch] = (top + (bot - top) * fy).round();
        }
      }
    }
    return img.Image.fromBytes(width: sw, height: sh, bytes: out.buffer, numChannels: 3);
  }

  // ---------------------------------------------------- warna kertas

  /// Warna kertas (foto sering keabu-abuan/kebiruan): median warna sel
  /// paling terang yang tidak jenuh.
  static int _paperOf(DetectedTable t) {
    final fills = [
      for (final c in t.cells)
        if (_sat(c.fill) < 30) c.fill
    ]..sort((a, b) => colorLum(b).compareTo(colorLum(a)));
    if (fills.isEmpty) return 0xFFFFFF;
    final top = fills.sublist(0, math.max(1, (fills.length * 0.5).ceil()));
    int med(int Function(int) f) {
      final v = top.map(f).toList()..sort();
      return v[v.length ~/ 2];
    }

    return (med(colorR) << 16) | (med(colorG) << 8) | med(colorB);
  }

  static int _sat(int c) =>
      math.max(colorR(c), math.max(colorG(c), colorB(c))) -
      math.min(colorR(c), math.min(colorG(c), colorB(c)));

  /// Koreksi warna terhadap kertas (kertas -> putih).
  static int _whiten(int c, int paper) {
    int ch(int v, int p) => p <= 0 ? v : math.min(255, v * 255 ~/ p);
    return (ch(colorR(c), colorR(paper)) << 16) |
        (ch(colorG(c), colorG(paper)) << 8) |
        ch(colorB(c), colorB(paper));
  }

  static TableInfo _toInfo(DetectedTable t, Raster r, double scale) {
    // lebar kolom/tinggi baris di tengah tabel
    final midY = (t.top + t.bottom) / 2, midX = (t.left + t.right) / 2;
    final colW = [
      for (var c = 0; c < t.colCount; c++)
        (t.xs[c + 1].at(midY) - t.xs[c].at(midY)) * scale
    ];
    final rowH = [
      for (var i = 0; i < t.rowCount; i++)
        (t.ys[i + 1].at(midX) - t.ys[i].at(midX)) * scale
    ];
    final paper = _paperOf(t);
    final inks = [for (final c in t.cells) _ink(r, c.box, c.fill)];
    // kotak centang hanya dipercaya bila mayoritas sel kolomnya juga kotak
    final colCells = <int, int>{}, colBoxes = <int, int>{};
    for (var i = 0; i < t.cells.length; i++) {
      final c = t.cells[i];
      if (c.colSpan != 1) continue;
      colCells[c.col] = (colCells[c.col] ?? 0) + 1;
      if (inks[i].checkbox > 0) colBoxes[c.col] = (colBoxes[c.col] ?? 0) + 1;
    }
    bool boxCol(int col) =>
        (colBoxes[col] ?? 0) >= 3 && (colBoxes[col] ?? 0) >= (colCells[col] ?? 1) * 0.5;
    // baris pertama-terakhir yang berisi kotak, per kolom
    final boxRows = <int, (int, int)>{};
    for (var i = 0; i < t.cells.length; i++) {
      final c = t.cells[i];
      if (inks[i].checkbox == 0 || c.colSpan != 1) continue;
      final p = boxRows[c.col];
      boxRows[c.col] = p == null ? (c.row, c.row) : (math.min(p.$1, c.row), math.max(p.$2, c.row));
    }
    int boxState(int i) {
      final c = t.cells[i];
      if (c.colSpan != 1 || !boxCol(c.col)) return 0;
      if (inks[i].checkbox > 0) return inks[i].checkbox;
      final range = boxRows[c.col];
      if (range == null || c.row < range.$1 || c.row > range.$2 || c.rowSpan != 1) return 0;
      // kotak tak terdeteksi bentuknya: tebak dari banyaknya tinta
      final area = math.max(1.0, (c.box[2] - c.box[0]) * (c.box[3] - c.box[1]));
      return inks[i].count / area > 0.12 ? -2 : -1; // negatif = tebakan
    }
    final cells = <CellInfo>[];
    for (var i = 0; i < t.cells.length; i++) {
      final c = t.cells[i];
      final ink = inks[i];
      cells.add(CellInfo(
        row: c.row,
        col: c.col,
        rowSpan: c.rowSpan,
        colSpan: c.colSpan,
        box: [for (final v in c.box) v * scale],
        fill: _whiten(c.fill, paper),
        hasInk: ink.count >= 4,
        ink: ink.color,
        align: ink.align,
        inkHeight: ink.height * scale,
        checkbox: boxState(i),
      ));
    }
    return TableInfo(
      colWidths: colW,
      rowHeights: rowH,
      left: t.xs.first.at(t.top) * scale,
      top: t.ys.first.at(t.left) * scale,
      cells: cells,
    );
  }

  static ({int count, int? color, CellAlign align, double height, int checkbox}) _ink(
      Raster r, List<double> box, int fill) {
    final w = box[2] - box[0], h = box[3] - box[1];
    final ix = math.max(2.0, w * 0.08), iy = math.max(2.0, h * 0.14);
    final x0 = (box[0] + ix).ceil().clamp(0, r.width - 1);
    final x1 = (box[2] - ix).floor().clamp(0, r.width - 1);
    final y0 = (box[1] + iy).ceil().clamp(0, r.height - 1);
    final y1 = (box[3] - iy).floor().clamp(0, r.height - 1);
    final bgL = colorLum(fill);
    final thr = math.min(200, bgL - 60);
    final l = r.lum;
    final soft = math.min(225, bgL - 25);
    var n = 0, sr = 0, sg = 0, sb = 0;
    var minX = 1 << 30, maxX = -1, minY = 1 << 30, maxY = -1;
    var sx0 = 1 << 30, sx1 = -1, sy0 = 1 << 30, sy1 = -1;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final i = y * r.width + x;
        if (l[i] < thr) {
          n++;
          sr += r.rgb[i * 3];
          sg += r.rgb[i * 3 + 1];
          sb += r.rgb[i * 3 + 2];
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    // kotak centang (garis tipis/abu-abu) dicari dengan ambang lebih lunak;
    // kotak tidak boleh menyentuh tepi area dalam (itu sisa garis sel)
    // area pencarian kotak: hampir setinggi sel (kotak sering memenuhi baris).
    // Ambil komponen gelap tersambung terbesar yang tidak menyentuh tepi
    // kiri/kanan (garis sel) — tekstur kertas berupa bintik kecil diabaikan.
    final cy0 = (box[1] + 2).ceil().clamp(0, r.height - 1);
    final cy1 = (box[3] - 2).floor().clamp(0, r.height - 1);
    final rw = x1 - x0 + 1, rh = cy1 - cy0 + 1;
    var box0 = 0;
    if (rw > 4 && rh > 4) {
      final seen = Uint8List(rw * rh);
      var bestArea = 0;
      for (var yy = 0; yy < rh; yy++) {
        for (var xx = 0; xx < rw; xx++) {
          final k = yy * rw + xx;
          if (seen[k] != 0 || l[(cy0 + yy) * r.width + x0 + xx] >= soft) continue;
          var cx0 = xx, cx1 = xx, cyA = yy, cyB = yy, count = 0;
          final stack = <int>[k];
          seen[k] = 1;
          while (stack.isNotEmpty) {
            final q = stack.removeLast();
            final qx = q % rw, qy = q ~/ rw;
            count++;
            if (qx < cx0) cx0 = qx;
            if (qx > cx1) cx1 = qx;
            if (qy < cyA) cyA = qy;
            if (qy > cyB) cyB = qy;
            for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
              final nx = qx + dx, ny = qy + dy;
              if (nx < 0 || ny < 0 || nx >= rw || ny >= rh) continue;
              final nk = ny * rw + nx;
              if (seen[nk] != 0 || l[(cy0 + ny) * r.width + x0 + nx] >= soft) continue;
              seen[nk] = 1;
              stack.add(nk);
            }
          }
          final area = (cx1 - cx0 + 1) * (cyB - cyA + 1);
          if (count < 12 || cx0 == 0 || cx1 == rw - 1 || area <= bestArea) continue;
          bestArea = area;
          sx0 = x0 + cx0;
          sx1 = x0 + cx1;
          sy0 = cy0 + cyA;
          sy1 = cy0 + cyB;
        }
      }
      if (bestArea > 0 && (sx1 - sx0 + 1) <= w * 0.6) {
        box0 = _checkbox(r, sx0, sy0, sx1, sy1, h, bgL);
      }
    }
    if (n < 4) {
      return (count: box0 > 0 ? 4 : n, color: null, align: CellAlign.center,
          height: box0 > 0 ? (sy1 - sy0 + 1).toDouble() : 0, checkbox: box0);
    }
    final cr = sr ~/ n, cg = sg ~/ n, cb = sb ~/ n;
    final sat = math.max(cr, math.max(cg, cb)) - math.min(cr, math.min(cg, cb));
    final color = sat > 50 ? (cr << 16) | (cg << 8) | cb : null;
    final leftGap = (minX - box[0]) / w;
    final rightGap = (box[2] - maxX) / w;
    final CellAlign align;
    if ((leftGap - rightGap).abs() < 0.15 && leftGap > 0.12) {
      align = CellAlign.center;
    } else if (rightGap < 0.15 && leftGap > 0.3) {
      align = CellAlign.right;
    } else {
      align = CellAlign.left;
    }
    return (
      count: n,
      color: color,
      align: align,
      height: (maxY - minY + 1).toDouble(),
      checkbox: box0,
    );
  }

  /// Kotak centang: tinta berbentuk bujur sangkar dengan tepi tegas.
  static int _checkbox(Raster r, int x0, int y0, int x1, int y1, double cellH, int bgL) {
    final bw = x1 - x0 + 1, bh = y1 - y0 + 1;
    if (bw < 6 || bh < 6) return 0;
    final ratio = bw / bh;
    if (ratio < 0.7 || ratio > 1.4 || bh < cellH * 0.3 || bh > cellH * 0.95) return 0;
    final l = r.lum;
    final thr = math.min(225, bgL - 25);
    bool on(int x, int y) =>
        x >= 0 && y >= 0 && x < r.width && y < r.height && l[y * r.width + x] < thr;
    // tepi kotak harus berupa garis utuh (toleransi 1 px ke dalam)
    var per = 0, perN = 0;
    for (var x = x0 + 1; x < x1; x++) {
      perN += 2;
      if (on(x, y0) || on(x, y0 + 1)) per++;
      if (on(x, y1) || on(x, y1 - 1)) per++;
    }
    for (var y = y0 + 1; y < y1; y++) {
      perN += 2;
      if (on(x0, y) || on(x0 + 1, y)) per++;
      if (on(x1, y) || on(x1 - 1, y)) per++;
    }
    if (per < perN * 0.85) return 0;
    // kotak terisi penuh (gaya checkbox Excel/Word yang dicentang)
    var fillOn = 0, fillN = 0, satSum = 0;
    for (var y = y0 + 2; y <= y1 - 2; y++) {
      for (var x = x0 + 2; x <= x1 - 2; x++) {
        fillN++;
        if (on(x, y)) fillOn++;
        final i = (y * r.width + x) * 3;
        satSum += math.max(r.rgb[i], math.max(r.rgb[i + 1], r.rgb[i + 2])) -
            math.min(r.rgb[i], math.min(r.rgb[i + 1], r.rgb[i + 2]));
      }
    }
    // isi berwarna jenuh = latar sel berwarna, bukan kotak centang
    if (fillN > 0 && satSum / fillN > 45) return 0;
    if (fillN > 0 && fillOn > fillN * 0.45) return 2;
    // isi: centang/tanda di bagian dalam
    final ix = (bw * 0.22).round(), iy = (bh * 0.22).round();
    final soft = math.min(215, bgL - 30);
    var inner = 0, innerN = 0;
    for (var y = y0 + iy; y <= y1 - iy; y++) {
      for (var x = x0 + ix; x <= x1 - ix; x++) {
        innerN++;
        if (l[y * r.width + x] < soft) inner++;
      }
    }
    if (innerN == 0) return 0;
    return inner > innerN * 0.08 ? 2 : 1;
  }

  /// Pita berwarna horizontal di luar tabel.
  static List<BandInfo> _bands(
      Raster r, List<DetectedTable> tables, double scale, int paper) {
    final w = r.width, h = r.height;
    final l = r.lum;
    final minRun = (w * 0.2).round();
    final paperLum = colorLum(paper);
    final rows = <(int, int, int)>[]; // y, x0, x1
    for (var y = 0; y < h; y++) {
      var start = -1, last = -100, on = 0;
      for (var x = 0; x <= w; x++) {
        var band = false;
        if (x < w) {
          final i = y * w + x;
          final c = (r.rgb[i * 3] << 16) | (r.rgb[i * 3 + 1] << 8) | r.rgb[i * 3 + 2];
          band = l[i] < math.min(215, paperLum - 25) && colorDistance(c, paper) > 60;
        }
        if (band) {
          if (start < 0 || x - last > 14) {
            if (start >= 0 && last - start >= minRun && on > 0.7 * (last - start + 1)) {
              rows.add((y, start, last));
            }
            start = x;
            on = 0;
          }
          last = x;
          on++;
        }
      }
      if (start >= 0 && last - start >= minRun && on > 0.7 * (last - start + 1)) {
        rows.add((y, start, last));
      }
    }
    // gabungkan baris berurutan
    final groups = <List<(int, int, int)>>[];
    for (final row in rows) {
      final g = groups.isEmpty ? null : groups.last;
      if (g != null &&
          row.$1 - g.last.$1 <= 2 &&
          math.min(row.$3, g.last.$3) - math.max(row.$2, g.last.$2) > minRun * 0.5) {
        g.add(row);
      } else {
        groups.add([row]);
      }
    }
    final out = <BandInfo>[];
    final unit = math.max(w, h) / 1600;
    for (final g in groups) {
      final top = g.first.$1.toDouble(), bottom = g.last.$1 + 1.0;
      if (bottom - top < 8 * unit || bottom - top > 90 * unit) continue;
      final xs0 = g.map((e) => e.$2).toList()..sort();
      final xs1 = g.map((e) => e.$3).toList()..sort();
      final left = xs0[xs0.length ~/ 2].toDouble();
      final right = xs1[xs1.length ~/ 2] + 1.0;
      final inside = tables.any((t) =>
          top >= t.top - 4 && bottom <= t.bottom + 4 &&
          left >= t.left - 4 && right <= t.right + 4);
      if (inside) continue;
      out.add(BandInfo(left * scale, top * scale, right * scale, bottom * scale,
          _whiten(_medianColor(r, left, top, right, bottom), paper)));
    }
    return out;
  }

  static int _medianColor(Raster r, double x0, double y0, double x1, double y1) {
    final rs = <int>[], gs = <int>[], bs = <int>[];
    final step = math.max(1, math.sqrt((x1 - x0) * (y1 - y0) / 2000).floor());
    for (var y = y0.floor(); y < y1.ceil() && y < r.height; y += step) {
      for (var x = x0.floor(); x < x1.ceil() && x < r.width; x += step) {
        rs.add(r.r(x, y));
        gs.add(r.g(x, y));
        bs.add(r.b(x, y));
      }
    }
    if (rs.isEmpty) return 0xFFFFFF;
    int med(List<int> v) => (v..sort())[v.length ~/ 2];
    return (med(rs) << 16) | (med(gs) << 8) | med(bs);
  }

  // ------------------------------------------------------------- mosaics

  static const _margin = 40, _rowGap = 44, _colGap = 150;
  static const _maxMosaicH = 2400, _maxCols = 3;

  static void _buildMosaics(
    img.Image full,
    List<TableInfo> tables,
    String workDir,
    int pageIndex,
    List<MosaicSlot> slots,
    List<String> outA,
    List<String> outB,
  ) {
    final crops = <(int, int, img.Image, int)>[]; // table, cell, crop, bgLum
    for (var ti = 0; ti < tables.length; ti++) {
      final t = tables[ti];
      for (var ci = 0; ci < t.cells.length; ci++) {
        final c = t.cells[ci];
        if (!c.hasInk) continue;
        final crop = _cropCell(full, c);
        if (crop != null) crops.add((ti, ci, crop, colorLum(c.fill)));
      }
    }
    if (crops.isEmpty) return;

    // susun ke kolom-kolom, lalu ke beberapa mosaik
    var mosaicIndex = 0;
    var i = 0;
    while (i < crops.length) {
      final columns = <List<int>>[];
      while (columns.length < _maxCols && i < crops.length) {
        final col = <int>[];
        var y = _margin;
        while (i < crops.length) {
          final h = crops[i].$3.height;
          if (col.isNotEmpty && y + h + _margin > _maxMosaicH) break;
          col.add(i);
          y += h + _rowGap;
          i++;
        }
        columns.add(col);
      }
      final colW = [
        for (final col in columns)
          col.map((k) => crops[k].$3.width).reduce(math.max)
      ];
      var width = _margin;
      final colX = <int>[];
      for (final w in colW) {
        colX.add(width);
        width += w + _colGap;
      }
      width = width - _colGap + _margin;
      var height = 0;
      for (final col in columns) {
        var y = _margin;
        for (final k in col) {
          y += crops[k].$3.height + _rowGap;
        }
        height = math.max(height, y - _rowGap + _margin);
      }
      final a = img.Image(width: width, height: height, numChannels: 3);
      img.fill(a, color: img.ColorRgb8(255, 255, 255));
      final b = img.Image(width: width, height: height, numChannels: 3);
      img.fill(b, color: img.ColorRgb8(255, 255, 255));
      for (var ci = 0; ci < columns.length; ci++) {
        var y = _margin;
        for (final k in columns[ci]) {
          final (ti, cellIdx, crop, bgLum) = crops[k];
          img.compositeImage(a, crop, dstX: colX[ci], dstY: y);
          img.compositeImage(b, _normalized(crop, bgLum), dstX: colX[ci], dstY: y);
          tables[ti].cells[cellIdx].slot = slots.length;
          slots.add(MosaicSlot(ti, cellIdx, mosaicIndex, colX[ci].toDouble(),
              y.toDouble(), crop.width.toDouble(), crop.height.toDouble()));
          y += crop.height + _rowGap;
        }
      }
      final pa = '$workDir/m${pageIndex + 1}_${mosaicIndex}_a.jpg';
      final pb = '$workDir/m${pageIndex + 1}_${mosaicIndex}_b.png';
      File(pa).writeAsBytesSync(img.encodeJpg(a, quality: 92));
      File(pb).writeAsBytesSync(img.encodePng(b, level: 1));
      outA.add(pa);
      outB.add(pb);
      mosaicIndex++;
    }
  }

  /// Potong isi sel (tanpa garis tepi), hapus sisa garis, perbesar.
  static img.Image? _cropCell(img.Image full, CellInfo c) {
    final w = c.box[2] - c.box[0], h = c.box[3] - c.box[1];
    final ix = math.max(3.0, w * 0.03), iy = math.max(3.0, h * 0.07);
    final x0 = (c.box[0] + ix).round().clamp(0, full.width - 1);
    final y0 = (c.box[1] + iy).round().clamp(0, full.height - 1);
    final x1 = (c.box[2] - ix).round().clamp(0, full.width);
    final y1 = (c.box[3] - iy).round().clamp(0, full.height);
    if (x1 - x0 < 6 || y1 - y0 < 6) return null;
    final crop = img.copyCrop(full, x: x0, y: y0, width: x1 - x0, height: y1 - y0);
    _eraseBorderLines(crop);
    final ch = crop.height.toDouble();
    var s = (80 / ch).clamp(1.0, 3.0);
    if (crop.width * s > 1000) s = math.max(0.5, 1000 / crop.width);
    if ((s - 1).abs() < 0.05) return crop;
    return img.copyResize(crop,
        width: (crop.width * s).round(),
        height: (crop.height * s).round(),
        interpolation: img.Interpolation.cubic);
  }

  static void _eraseBorderLines(img.Image im) {
    final w = im.width, h = im.height;
    int lumAt(int x, int y) {
      final p = im.getPixel(x, y);
      return (p.r.toInt() * 299 + p.g.toInt() * 587 + p.b.toInt() * 114) ~/ 1000;
    }

    final white = img.ColorRgb8(255, 255, 255);
    // sisa garis = ruas gelap hampir sepanjang potongan (angka tidak begitu)
    int longest(int n, bool Function(int i) dark) {
      var best = 0, run = 0, gap = 0;
      for (var i = 0; i < n; i++) {
        if (dark(i)) {
          run += gap + 1;
          gap = 0;
          if (run > best) best = run;
        } else if (run > 0 && gap < 2) {
          gap++;
        } else {
          run = 0;
          gap = 0;
        }
      }
      return best;
    }

    final bandY = math.max(2, (h * 0.18).round());
    for (var y = 0; y < h; y++) {
      if (y >= bandY && y < h - bandY) continue;
      if (longest(w, (x) => lumAt(x, y) < 190) > w * 0.6) {
        for (var x = 0; x < w; x++) {
          im.setPixel(x, y, white);
        }
      }
    }
    final bandX = math.max(2, (w * 0.12).round());
    for (var x = 0; x < w; x++) {
      if (x >= bandX && x < w - bandX) continue;
      if (longest(h, (y) => lumAt(x, y) < 190) > h * 0.75) {
        for (var y = 0; y < h; y++) {
          im.setPixel(x, y, white);
        }
      }
    }
  }

  /// Varian B: abu-abu dengan latar sel dinormalisasi ke putih & kontras
  /// diperkuat, membantu tulisan tipis atau sel berwarna.
  static img.Image _normalized(img.Image crop, int bgLum) {
    final src = crop.numChannels == 3 ? crop : crop.convert(numChannels: 3);
    final w = src.width, h = src.height;
    final rgb = src.getBytes(order: img.ChannelOrder.rgb);
    // latar = persentil 80 luminans potongan (lebih andal dari warna sel)
    final hist = List<int>.filled(256, 0);
    final l = Uint8List(w * h);
    for (var i = 0, j = 0; i < l.length; i++, j += 3) {
      final v = (rgb[j] * 299 + rgb[j + 1] * 587 + rgb[j + 2] * 114) ~/ 1000;
      l[i] = v;
      hist[v]++;
    }
    var acc = 0, p80 = 255;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= l.length * 0.8) {
        p80 = v;
        break;
      }
    }
    final bg = math.max(60, p80);
    final out = Uint8List(w * h * 3);
    for (var i = 0; i < l.length; i++) {
      final v = math.min(255, l[i] * 255 ~/ bg);
      final s = ((v - 70) * 255 ~/ 150).clamp(0, 255);
      out[i * 3] = s;
      out[i * 3 + 1] = s;
      out[i * 3 + 2] = s;
    }
    return img.Image.fromBytes(
        width: w, height: h, bytes: out.buffer, numChannels: 3);
  }
}
