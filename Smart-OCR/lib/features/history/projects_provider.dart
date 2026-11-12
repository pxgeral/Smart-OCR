import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_settings.dart';
import '../../models/converted_content.dart';
import '../../models/enums.dart';
import '../../models/project_item.dart';
import '../../services/providers.dart';
import '../../services/settings_provider.dart';
import 'project_repository.dart';

class ProjectsNotifier extends Notifier<List<ProjectItem>> {
  @override
  List<ProjectItem> build() => ref.read(projectRepositoryProvider).all();

  ProjectRepository get _repo => ref.read(projectRepositoryProvider);

  Future<void> add(ProjectItem p) async {
    await _repo.save(p);
    state = [p, ...state];
  }

  Future<void> rename(ProjectItem p, String name) =>
      _update(p.copyWith(name: name));

  Future<void> toggleFavorite(ProjectItem p) =>
      _update(p.copyWith(favorite: !p.favorite));

  Future<void> remove(ProjectItem p) async {
    final contents = ref.read(contentRepositoryProvider);
    final c = contents.load(p.id);
    String? dir;
    if (c != null && c.pages.isNotEmpty && c.pages.first.imagePath.isNotEmpty) {
      dir = File(c.pages.first.imagePath).parent.path;
    }
    await contents.delete(p.id, projectDir: dir);
    await _repo.delete(p);
    state = state.where((x) => x.id != p.id).toList();
  }

  /// Simpan isi yang sudah dikoreksi lalu buat ulang file keluaran.
  /// Format sama -> file lama ditimpa; format lain -> file baru.
  Future<ProjectItem> saveAndExport(
      ProjectItem p, ConvertedContent content, OutputType type) async {
    await ref.read(contentRepositoryProvider).save(p.id, content);
    final file = await ref.read(exportServiceProvider).export(
          type: type,
          baseName: p.name,
          content: content,
          images: [for (final pg in content.pages) pg.imagePath],
          options: ExportOptions.from(ref.read(settingsProvider)),
          replacePath: type == p.outputType ? p.outputPath : null,
        );
    final n = p.copyWith(outputPath: file.path, outputType: type);
    await _update(n);
    return n;
  }

  Future<void> _update(ProjectItem n) async {
    await _repo.save(n);
    state = [for (final x in state) x.id == n.id ? n : x];
  }
}

final projectsProvider =
    NotifierProvider<ProjectsNotifier, List<ProjectItem>>(ProjectsNotifier.new);

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

final searchQueryProvider =
    NotifierProvider<SearchQuery, String>(SearchQuery.new);

/// Pencarian nama; favorit di atas, lalu terbaru.
final filteredProjectsProvider = Provider<List<ProjectItem>>((ref) {
  final q = ref.watch(searchQueryProvider).trim().toLowerCase();
  final all = ref.watch(projectsProvider);
  final list = q.isEmpty
      ? [...all]
      : all.where((p) => p.name.toLowerCase().contains(q)).toList();
  list.sort((a, b) {
    if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
    return b.createdAt.compareTo(a.createdAt);
  });
  return list;
});
