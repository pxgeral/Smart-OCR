import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../models/enums.dart';
import '../../models/project_item.dart';
import '../../services/providers.dart';
import '../review/review_screen.dart';
import 'projects_provider.dart';

enum _Action { open, review, export, share, rename, location, delete }

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(filteredProjectsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Cari proyek',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: ref.read(searchQueryProvider.notifier).set,
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('Belum ada riwayat'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => _Tile(item: items[i]),
                ),
        ),
      ],
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.item});
  final ProjectItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(projectsProvider.notifier);
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(item.thumbnail),
          width: 48,
          height: 48,
          cacheWidth: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(
              width: 48, height: 48, child: Icon(Icons.description)),
        ),
      ),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${item.outputType.label} - ${displayDate(item.createdAt)}'),
      onTap: () => ref.read(fileServiceProvider).open(item.outputPath),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(item.favorite ? Icons.star : Icons.star_border),
            onPressed: () => notifier.toggleFavorite(item),
          ),
          PopupMenuButton<_Action>(
            onSelected: (a) => _handle(context, ref, a),
            itemBuilder: (_) => [
              const PopupMenuItem(value: _Action.open, child: Text('Buka')),
              if (ref.read(contentRepositoryProvider).has(item.id)) ...const [
                PopupMenuItem(value: _Action.review, child: Text('Tinjau & koreksi')),
                PopupMenuItem(value: _Action.export, child: Text('Ekspor ke format lain')),
              ],
              const PopupMenuItem(value: _Action.share, child: Text('Bagikan')),
              const PopupMenuItem(value: _Action.rename, child: Text('Ganti nama')),
              const PopupMenuItem(value: _Action.location, child: Text('Lokasi file')),
              const PopupMenuItem(value: _Action.delete, child: Text('Hapus')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handle(BuildContext context, WidgetRef ref, _Action a) async {
    final files = ref.read(fileServiceProvider);
    final notifier = ref.read(projectsProvider.notifier);
    switch (a) {
      case _Action.open:
        await files.open(item.outputPath);
      case _Action.review:
        if (!context.mounted) return;
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ReviewScreen(project: item),
        ));
      case _Action.export:
        if (!context.mounted) return;
        final type = await showDialog<OutputType>(
          context: context,
          builder: (c) => SimpleDialog(
            title: const Text('Ekspor ke'),
            children: [
              for (final t in OutputType.values)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, t),
                  child: Text('${t.label} (.${t.ext})'),
                ),
            ],
          ),
        );
        final content = ref.read(contentRepositoryProvider).load(item.id);
        if (type == null || content == null) return;
        final n = await notifier.saveAndExport(item, content, type);
        await files.open(n.outputPath);
      case _Action.share:
        await files.share(item.outputPath);
      case _Action.rename:
        final ctrl = TextEditingController(text: item.name);
        final name = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Ganti nama'),
            content: TextField(controller: ctrl, autofocus: true),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, ctrl.text.trim()),
                  child: const Text('Simpan')),
            ],
          ),
        );
        ctrl.dispose();
        if (name != null && name.isNotEmpty) await notifier.rename(item, name);
      case _Action.location:
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Lokasi file'),
            content: SelectableText(item.outputPath),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Tutup')),
            ],
          ),
        );
      case _Action.delete:
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Hapus proyek?'),
            content: Text('"${item.name}" dan file hasilnya akan dihapus.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Hapus')),
            ],
          ),
        );
        if (ok == true) await notifier.remove(item);
    }
  }
}
