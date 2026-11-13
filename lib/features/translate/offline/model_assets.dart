import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants.dart';

/// Model terjemahan offline yang ikut di dalam APK (assets/models/<arah>/).
/// Diunduh CI saat membangun APK (tool/ambil_model.sh), bukan saat dipakai.
abstract final class OfflineModelAssets {
  static const files = ['encoder.onnx', 'decoder.onnx', 'vocab.json', 'source.spm'];

  static String assetPath(String direction, String file) =>
      'assets/models/$direction/$file';

  /// true bila semua berkas model arah ini ikut terkemas di aplikasi.
  static Future<bool> available(String direction) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final all = manifest.listAssets().toSet();
      return files.every((f) => all.contains(assetPath(direction, f)));
    } catch (_) {
      return false;
    }
  }

  /// Menyalin model dari aset ke penyimpanan aplikasi (sekali per versi)
  /// karena ONNX Runtime perlu membacanya dari berkas. Mengembalikan foldernya.
  static Future<String> prepare(String direction,
      {void Function(String message)? onStatus}) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/offline_mt/$direction');
    final marker = File('${dir.path}/.siap-${AppConstants.version}');
    if (await marker.exists()) return dir.path;

    onStatus?.call('Menyiapkan model terjemahan bawaan (sekali saja)...');
    await dir.create(recursive: true);
    await for (final e in dir.list()) {
      if (e is File && e.uri.pathSegments.last.startsWith('.siap-')) {
        await e.delete();
      }
    }
    for (final f in files) {
      final data = await rootBundle.load(assetPath(direction, f));
      await File('${dir.path}/$f').writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    await marker.writeAsString('ok');
    return dir.path;
  }
}
