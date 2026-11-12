import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Gambar RGB 8-bit sederhana (baris demi baris) untuk analisis piksel cepat.
class Raster {
  Raster(this.width, this.height, this.rgb)
      : assert(rgb.length == width * height * 3);

  factory Raster.fromImage(img.Image image) {
    final src = image.numChannels == 3 && image.bitsPerChannel == 8
        ? image
        : image.convert(numChannels: 3, format: img.Format.uint8);
    final bytes = src.getBytes(order: img.ChannelOrder.rgb);
    return Raster(src.width, src.height, Uint8List.fromList(bytes));
  }

  final int width, height;
  final Uint8List rgb;

  Uint8List? _lum;

  /// Luminans 0..255 per piksel (cache).
  Uint8List get lum {
    final cached = _lum;
    if (cached != null) return cached;
    final out = Uint8List(width * height);
    for (var i = 0, j = 0; i < out.length; i++, j += 3) {
      out[i] = (rgb[j] * 299 + rgb[j + 1] * 587 + rgb[j + 2] * 114) ~/ 1000;
    }
    return _lum = out;
  }

  int r(int x, int y) => rgb[(y * width + x) * 3];
  int g(int x, int y) => rgb[(y * width + x) * 3 + 1];
  int b(int x, int y) => rgb[(y * width + x) * 3 + 2];

  /// Warna latar sebuah kotak: median warna dari 60% piksel paling terang
  /// (tinta diabaikan). Mengembalikan 0xRRGGBB.
  int backgroundColor(double x0, double y0, double x1, double y1,
      {double insetX = 0.12, double insetY = 0.15}) {
    final w = x1 - x0, h = y1 - y0;
    final px = math.max(2.0, w * insetX), py = math.max(2.0, h * insetY);
    final ax = (x0 + px).floor().clamp(0, width - 1);
    final bx = (x1 - px).ceil().clamp(0, width);
    final ay = (y0 + py).floor().clamp(0, height - 1);
    final by = (y1 - py).ceil().clamp(0, height);
    if (bx - ax < 2 || by - ay < 2) return 0xFFFFFF;
    // sampling agar cepat pada sel besar
    final step = math.max(1, math.sqrt((bx - ax) * (by - ay) / 1600).floor());
    final l = lum;
    final hist = List<int>.filled(256, 0);
    var n = 0;
    for (var y = ay; y < by; y += step) {
      for (var x = ax; x < bx; x += step) {
        hist[l[y * width + x]]++;
        n++;
      }
    }
    if (n == 0) return 0xFFFFFF;
    // ambang persentil 40
    var acc = 0, thr = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= n * 0.4) {
        thr = v;
        break;
      }
    }
    final rs = <int>[], gs = <int>[], bs = <int>[];
    for (var y = ay; y < by; y += step) {
      for (var x = ax; x < bx; x += step) {
        final i = y * width + x;
        if (l[i] >= thr) {
          rs.add(rgb[i * 3]);
          gs.add(rgb[i * 3 + 1]);
          bs.add(rgb[i * 3 + 2]);
        }
      }
    }
    if (rs.isEmpty) return 0xFFFFFF;
    return (_median(rs) << 16) | (_median(gs) << 8) | _median(bs);
  }

  static int _median(List<int> v) {
    v.sort();
    return v[v.length ~/ 2];
  }
}

int colorR(int c) => (c >> 16) & 0xFF;
int colorG(int c) => (c >> 8) & 0xFF;
int colorB(int c) => c & 0xFF;
int colorLum(int c) =>
    (colorR(c) * 299 + colorG(c) * 587 + colorB(c) * 114) ~/ 1000;

/// Jarak maksimum per kanal.
int colorDistance(int a, int b) => math.max(
    (colorR(a) - colorR(b)).abs(),
    math.max((colorG(a) - colorG(b)).abs(), (colorB(a) - colorB(b)).abs()));

/// Apakah warna cukup berbeda dari kertas putih untuk dijadikan warna sel.
bool isFillColor(int c, {int paper = 0xFFFFFF}) => colorDistance(c, paper) > 16;

String colorHex(int c) =>
    (c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
