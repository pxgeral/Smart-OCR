import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smart_ocr_converter/core/raster.dart';
import 'package:smart_ocr_converter/features/converter/table_structure.dart';

/// Tabel sintetis: kepala berwarna dengan sel gabungan + badan 5 baris.
///
///  +-------+-----------------------+
///  |  No   |   Ulangan (biru)      |   baris 0 (No gabung 2 baris)
///  |       +-----+-----+-----------+
///  |       |  A  |  B  |  Rata     |   baris 1
///  +-------+-----+-----+-----------+
///  | ...   | ... | ... |  ...      |   baris 2..6
img.Image _synthetic() {
  const w = 900, h = 600;
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(255, 255, 255));
  const xs = [100, 220, 400, 580, 800];
  const ys = [80, 130, 180, 230, 280, 330, 380, 430];
  // kepala biru
  img.fillRect(im, x1: xs[1], y1: ys[0], x2: xs[4], y2: ys[1], color: img.ColorRgb8(91, 155, 213));
  img.fillRect(im, x1: xs[0], y1: ys[0], x2: xs[1], y2: ys[2], color: img.ColorRgb8(47, 117, 181));
  img.fillRect(im, x1: xs[1], y1: ys[1], x2: xs[4], y2: ys[2], color: img.ColorRgb8(189, 215, 238));
  final black = img.ColorRgb8(0, 0, 0);
  void h0(int y, int x0, int x1) => img.fillRect(im, x1: x0, y1: y - 1, x2: x1, y2: y + 1, color: black);
  void v0(int x, int y0, int y1) => img.fillRect(im, x1: x - 1, y1: y0, x2: x + 1, y2: y1, color: black);
  // garis horizontal: baris 1 (di bawah "Ulangan") tidak melewati kolom No
  for (var i = 0; i < ys.length; i++) {
    if (i == 1) {
      h0(ys[i], xs[1], xs[4]);
    } else {
      h0(ys[i], xs[0], xs[4]);
    }
  }
  // garis vertikal: di dalam "Ulangan" (baris 0) tidak ada pemisah A|B|Rata
  for (var j = 0; j < xs.length; j++) {
    if (j == 2 || j == 3) {
      v0(xs[j], ys[1], ys.last);
    } else {
      v0(xs[j], ys[0], ys.last);
    }
  }
  return im;
}

void main() {
  test('mendeteksi grid, sel gabungan, dan warna kepala', () {
    final raster = Raster.fromImage(_synthetic());
    final tables = TableStructureDetector(raster).detect();
    expect(tables, hasLength(1));
    final t = tables.first;
    expect(t.colCount, 4);
    expect(t.rowCount, 7);

    DetectedCell at(int r, int c) =>
        t.cells.firstWhere((x) => x.row == r && x.col == c);
    final no = at(0, 0);
    expect(no.rowSpan, 2, reason: 'No digabung 2 baris');
    final ul = at(0, 1);
    expect(ul.colSpan, 3, reason: 'Ulangan digabung 3 kolom');
    expect(at(1, 1).colSpan, 1);
    expect(colorDistance(ul.fill, 0x5B9BD5), lessThan(20));
    expect(colorDistance(no.fill, 0x2F75B5), lessThan(20));
    expect(isFillColor(at(3, 2).fill), isFalse);
    // 1 (No) + 1 (Ulangan) + 3 (A,B,Rata) + 5 baris x 4 kolom
    expect(t.cells.length, 1 + 1 + 3 + 20);
  });

  test('gambar tanpa garis tidak menghasilkan tabel', () {
    final im = img.Image(width: 600, height: 400, numChannels: 3);
    img.fill(im, color: img.ColorRgb8(255, 255, 255));
    img.drawString(im, 'Halo dunia', font: img.arial24, x: 50, y: 50, color: img.ColorRgb8(0, 0, 0));
    expect(TableStructureDetector(Raster.fromImage(im)).detect(), isEmpty);
  });
}
