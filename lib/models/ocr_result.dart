import 'enums.dart';

/// Satu baris/kata hasil OCR beserta posisinya (px pada gambar sumber).
class OcrBox {
  const OcrBox({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence = 1,
    this.chars = const [],
  });

  final String text;
  final double left, top, right, bottom, confidence;

  /// Posisi tiap karakter (bila tersedia dari mesin OCR): [kiri, kanan]
  /// sejajar dengan [text]. Dipakai untuk memecah kata yang melewati
  /// garis kolom.
  final List<List<double>> chars;

  double get width => right - left;
  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;

  Map<String, dynamic> toMap() => {
        't': text,
        'l': left,
        'tp': top,
        'r': right,
        'b': bottom,
        'c': confidence,
        if (chars.isNotEmpty) 'ch': chars,
      };

  factory OcrBox.fromMap(Map<String, dynamic> m) => OcrBox(
        text: m['t'] as String,
        left: (m['l'] as num).toDouble(),
        top: (m['tp'] as num).toDouble(),
        right: (m['r'] as num).toDouble(),
        bottom: (m['b'] as num).toDouble(),
        confidence: (m['c'] as num).toDouble(),
        chars: [
          for (final c in (m['ch'] as List? ?? const []))
            [for (final v in c as List) (v as num).toDouble()]
        ],
      );
}

class OcrPage {
  const OcrPage({
    required this.index,
    required this.width,
    required this.height,
    required this.boxes,
  });

  final int index;
  final double width, height;
  final List<OcrBox> boxes;

  String get text => boxes.map((b) => b.text).join('\n');

  Map<String, dynamic> toMap() => {
        'i': index,
        'w': width,
        'h': height,
        'bx': boxes.map((b) => b.toMap()).toList(),
      };

  factory OcrPage.fromMap(Map<String, dynamic> m) => OcrPage(
        index: m['i'] as int,
        width: (m['w'] as num).toDouble(),
        height: (m['h'] as num).toDouble(),
        boxes: (m['bx'] as List)
            .map((e) => OcrBox.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class OcrResult {
  const OcrResult({required this.engine, required this.pages});

  final OcrEngineId engine;
  final List<OcrPage> pages;

  String get text => pages.map((p) => p.text).join('\n\n');
  bool get isEmpty => pages.every((p) => p.boxes.isEmpty);

  Map<String, dynamic> toMap() => {
        'e': engine.name,
        'p': pages.map((p) => p.toMap()).toList(),
      };

  factory OcrResult.fromMap(Map<String, dynamic> m) => OcrResult(
        engine: OcrEngineId.values.byName(m['e'] as String),
        pages: (m['p'] as List)
            .map((e) => OcrPage.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
