import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

import '../../core/failure.dart';
import '../../models/enums.dart';
import '../../models/ocr_result.dart';
import 'ocr_engine.dart';

/// Menjalankan OCR per halaman: cache dulu, lalu mesin berurutan (fallback).
class OcrService {
  OcrService(this._engines, this._cache);

  final List<OcrEngine> _engines; // urutan prioritas
  final Box<String> _cache;

  Future<OcrResult> recognizeAll(
    List<String> paths, {
    void Function(int done, int total)? onProgress,
  }) async {
    final pages = <OcrPage>[];
    var used = _engines.first.id;
    for (var i = 0; i < paths.length; i++) {
      final key = await _key(paths[i]);
      final hit = _cache.get(key);
      if (hit != null) {
        final c = OcrPage.fromMap(jsonDecode(hit) as Map<String, dynamic>);
        pages.add(OcrPage(
            index: i, width: c.width, height: c.height, boxes: c.boxes));
      } else {
        final (page, id) = await _recognize(paths[i], i);
        used = id;
        if (_cache.length > 300) await _cache.clear();
        await _cache.put(key, jsonEncode(page.toMap()));
        pages.add(page);
      }
      onProgress?.call(i + 1, paths.length);
    }
    return OcrResult(engine: used, pages: pages);
  }

  /// OCR tanpa cache (mis. untuk gambar mosaik sementara).
  Future<OcrPage> recognizeUncached(String path, int index) async =>
      (await _recognize(path, index)).$1;

  Future<(OcrPage, OcrEngineId)> _recognize(String path, int index) async {
    Object? last;
    for (final e in _engines) {
      try {
        return (await e.recognize(path, index), e.id);
      } catch (err) {
        last = err;
      }
    }
    throw OcrFailure('OCR gagal: $last');
  }

  Future<String> _key(String path) async {
    final s = await File(path).stat();
    return Object.hash(path, s.size, s.modified.millisecondsSinceEpoch)
        .toString();
  }

  Future<void> clearCache() async {
    await _cache.clear();
  }

  Future<void> dispose() async {
    for (final e in _engines) {
      await e.dispose();
    }
  }
}
