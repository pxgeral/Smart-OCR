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
  });

  final int row, col, rowSpan, colSpan;
  final List<double> box; // full-res px
  final int fill;
  final bool hasInk;
  final int? ink; // warna tinta bila berwarna (mis. pulpen biru)
  final CellAlign align;
  final double inkHeight; // full-res px
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
    File(normPath).writeAsBytesSync(
        img.encodeJpg(full, quality: AppConstants.jpegQuality));

    if (!detectTables) {
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

    final ws = math.min(1.0, workSide / math.max(full.width, full.height));
    final work = ws < 1
        ? img.copyResize(full,
            width: (full.width * ws).round(),
            height: (full.height * ws).round(),
            interpolation: img.Interpolation.linear)
        : full;
    final raster = Raster.fromImage(work);
    final scale = full.width / work.width; // work -> full

    final detected = TableStructureDetector(raster).detect();
    final tables = <TableInfo>[
      for (final t in detected) _toInfo(t, raster, scale),
    ];
    final bands = _bands(raster, detected, scale);

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
    final cells = <CellInfo>[];
    for (final c in t.cells) {
      final ink = _ink(r, c.box, c.fill);
      cells.add(CellInfo(
        row: c.row,
        col: c.col,
        rowSpan: c.rowSpan,
        colSpan: c.colSpan,
        box: [for (final v in c.box) v * scale],
        fill: c.fill,
        hasInk: ink.count >= 4,
        ink: ink.color,
        align: ink.align,
        inkHeight: ink.height * scale,
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

  static ({int count, int? color, CellAlign align, double height}) _ink(
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
    var n = 0, sr = 0, sg = 0, sb = 0;
    var minX = 1 << 30, maxX = -1, minY = 1 << 30, maxY = -1;
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
    if (n < 4) {
      return (count: n, color: null, align: CellAlign.left, height: 0);
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
    return (count: n, color: color, align: align, height: (maxY - minY + 1).toDouble());
  }

  /// Pita berwarna horizontal di luar tabel.
  static List<BandInfo> _bands(
      Raster r, List<DetectedTable> tables, double scale) {
    final w = r.width, h = r.height;
    final l = r.lum;
    final minRun = (w * 0.2).round();
    final rows = <(int, int, int)>[]; // y, x0, x1
    for (var y = 0; y < h; y++) {
      var start = -1, last = -100, on = 0;
      for (var x = 0; x <= w; x++) {
        var band = false;
        if (x < w) {
          final i = y * w + x;
          final c = (r.rgb[i * 3] << 16) | (r.rgb[i * 3 + 1] << 8) | r.rgb[i * 3 + 2];
          band = l[i] < 215 && colorDistance(c, 0xFFFFFF) > 60;
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
          _medianColor(r, left, top, right, bottom)));
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
