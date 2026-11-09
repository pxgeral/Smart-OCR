import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../models/enums.dart';
import '../../models/ocr_result.dart';
import 'ocr_engine.dart';

/// Offline, model Latin (Indonesia, Inggris, angka). Hasil per KATA agar
/// converter bisa memisahkan sel tabel dari jarak antar kata.
class MlKitOcrEngine implements OcrEngine {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  OcrEngineId get id => OcrEngineId.mlkit;

  @override
  Future<OcrPage> recognize(String imagePath, int pageIndex) async {
    final result =
        await _recognizer.processImage(InputImage.fromFilePath(imagePath));
    final boxes = <OcrBox>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        for (final w in line.elements) {
          if (w.text.trim().isEmpty) continue;
          final r = w.boundingBox;
          boxes.add(OcrBox(
            text: w.text,
            left: r.left,
            top: r.top,
            right: r.right,
            bottom: r.bottom,
          ));
        }
      }
    }
    final size = await _imageSize(imagePath);
    return OcrPage(
      index: pageIndex,
      width: size.$1,
      height: size.$2,
      boxes: boxes,
    );
  }

  Future<(double, double)> _imageSize(String path) async {
    final buffer =
        await ui.ImmutableBuffer.fromUint8List(await File(path).readAsBytes());
    try {
      final d = await ui.ImageDescriptor.encoded(buffer);
      final size = (d.width.toDouble(), d.height.toDouble());
      d.dispose();
      return size;
    } finally {
      buffer.dispose();
    }
  }

  @override
  Future<void> dispose() => _recognizer.close();
}
