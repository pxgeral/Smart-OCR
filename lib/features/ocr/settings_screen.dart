import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../services/providers.dart';
import '../../services/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return ListView(
      children: [
        const _Header('Pembacaan'),
        SwitchListTile(
          secondary: const Icon(Icons.draw),
          title: const Text('Verifikasi tulisan tangan'),
          subtitle: const Text(
              'Setiap sel tabel dibaca ulang dari potongan gambar (2 varian) lalu '
              'dicocokkan dengan pola kolom & rumus rata-rata. Lebih lambat, lebih akurat.'),
          value: s.cellOcr,
          onChanged: (v) => n.update(s.copyWith(cellOcr: v)),
        ),
        ListTile(
          leading: const Icon(Icons.spellcheck),
          title: const Text('Kamus kata'),
          subtitle: Text(s.dictionary.isEmpty
              ? 'Tambahkan nama menu, nama orang, istilah yang sering muncul'
              : '${s.dictionary.length} kata: ${s.dictionary.take(6).join(', ')}'
                  '${s.dictionary.length > 6 ? ', ...' : ''}'),
          onTap: () => _editDictionary(context, ref),
        ),
        const _Header('Hasil Word / Excel'),
        SwitchListTile(
          secondary: const Icon(Icons.palette),
          title: const Text('Pertahankan warna'),
          subtitle: const Text('Warna sel, pita judul, dan warna tinta seperti aslinya'),
          value: s.keepColors,
          onChanged: (v) => n.update(s.copyWith(keepColors: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.checklist),
          title: const Text('Lembar "Verifikasi" di Excel'),
          subtitle: const Text('Daftar sel yang perlu dicek beserta tautan ke selnya'),
          value: s.reviewSheet,
          onChanged: (v) => n.update(s.copyWith(reviewSheet: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.highlight),
          title: const Text('Tandai sel meragukan'),
          subtitle: const Text('Sel perlu cek diberi warna kuning/merah di file hasil'),
          value: s.markInExcel,
          onChanged: (v) => n.update(s.copyWith(markInExcel: v)),
        ),
        const _Header('Lainnya'),
        const ListTile(
          leading: Icon(Icons.text_fields),
          title: Text('Mesin OCR'),
          subtitle: Text('Google ML Kit (offline) - Indonesia, Inggris, angka'),
        ),
        ListTile(
          leading: const Icon(Icons.delete_sweep),
          title: const Text('Hapus cache OCR'),
          subtitle: const Text('Hasil OCR tersimpan agar halaman yang sama tidak diproses ulang'),
          onTap: () async {
            await ref.read(ocrServiceProvider).clearCache();
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Cache OCR dihapus')));
            }
          },
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text(AppConstants.appName),
          subtitle: Text('Versi ${AppConstants.version}'),
        ),
      ],
    );
  }

  Future<void> _editDictionary(BuildContext context, WidgetRef ref) async {
    final s = ref.read(settingsProvider);
    final ctrl = TextEditingController(text: s.dictionary.join('\n'));
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kamus kata'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: ctrl,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Satu kata/frasa per baris\nmis. Nasi\nAyam\nTempe',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Simpan')),
        ],
      ),
    );
    ctrl.dispose();
    if (r == null) return;
    final words = <String>{
      for (final w in r.split('\n'))
        if (w.trim().isNotEmpty) w.trim()
    }.toList();
    await ref.read(settingsProvider.notifier).update(s.copyWith(dictionary: words));
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
