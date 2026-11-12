import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

import '../../models/project_item.dart';

class ProjectRepository {
  ProjectRepository(this._box);
  final Box<String> _box;

  List<ProjectItem> all() => [
        for (final s in _box.values)
          ProjectItem.fromMap(jsonDecode(s) as Map<String, dynamic>),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> save(ProjectItem p) => _box.put(p.id, jsonEncode(p.toMap()));

  /// Hapus data riwayat beserta file hasil dan thumbnail-nya.
  Future<void> delete(ProjectItem p) async {
    await _box.delete(p.id);
    for (final path in [p.outputPath, p.thumbnail]) {
      if (path.isEmpty) continue;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}
