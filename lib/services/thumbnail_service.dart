import 'dart:io';
import 'dart:ui' as ui;

import 'file_service.dart';

class ThumbnailService {
  ThumbnailService(this._files);
  final FileService _files;

  /// Mengembalikan path PNG kecil, atau '' bila gagal (thumbnail opsional).
  Future<String> create(String imagePath, String id) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (data == null) return '';
      final dir = await _files.subDir('thumbs');
      final out = File('${dir.path}/$id.png');
      await out.writeAsBytes(data.buffer.asUint8List());
      return out.path;
    } catch (_) {
      return '';
    }
  }
}
