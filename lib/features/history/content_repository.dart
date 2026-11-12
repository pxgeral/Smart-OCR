import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

import '../../models/converted_content.dart';

/// Menyimpan hasil konversi terstruktur per proyek agar bisa ditinjau,
/// diedit, dan diekspor ulang dari Riwayat.
class ContentRepository {
  ContentRepository(this._box);
  final Box<String> _box;

  ConvertedContent? load(String id) {
    final raw = _box.get(id);
    if (raw == null) return null;
    try {
      return ConvertedContent.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  bool has(String id) => _box.containsKey(id);

  Future<void> save(String id, ConvertedContent c) =>
      _box.put(id, jsonEncode(c.toMap()));

  Future<void> delete(String id, {String? projectDir}) async {
    await _box.delete(id);
    if (projectDir == null || projectDir.isEmpty) return;
    try {
      final d = Directory(projectDir);
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }
}
