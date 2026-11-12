import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../services/providers.dart';
import '../../services/settings_provider.dart';
import 'gemini_reader.dart';

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
        const _Header('AI Gemini (opsional, online)'),
        SwitchListTile(
          secondary: const Icon(Icons.auto_awesome),
          title: const Text('Baca isi tabel dengan AI Gemini'),
          subtitle: Text(s.aiKey.trim().isEmpty
              ? 'Perlu kunci API gratis dari aistudio.google.com. Gambar tabel dikirim ke Google.'
              : 'Struktur tabel tetap dari perangkat; isi sel dibaca Gemini lalu dicek pola & rumus.'),
          value: s.aiEnabled,
          onChanged: (v) async {
            if (v && s.aiKey.trim().isEmpty) {
              await _editKey(context, ref);
              final now = ref.read(settingsProvider);
              if (now.aiKey.trim().isEmpty) return;
              await n.update(now.copyWith(aiEnabled: true));
              return;
            }
            await n.update(s.copyWith(aiEnabled: v));
          },
        ),
        ListTile(
          leading: const Icon(Icons.key),
          title: const Text('Kunci API Gemini'),
          subtitle: Text(s.aiKey.trim().isEmpty
              ? 'Belum diisi'
              : s.aiKey.trim().length <= 4
                  ? '••••'
                  : '••••••${s.aiKey.trim().substring(s.aiKey.trim().length - 4)}'),
          onTap: () => _editKey(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.memory),
          title: const Text('Model'),
          subtitle: Text(s.aiModel.trim().isEmpty ? '${GeminiReader.defaultModel} (bawaan)' : s.aiModel),
          onTap: () => _editModel(context, ref),
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

  Future<void> _editKey(BuildContext context, WidgetRef ref) async {
    final s = ref.read(settingsProvider);
    final ctrl = TextEditingController(text: s.aiKey);
    var testing = false;
    String? result;
    final r = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Kunci API Gemini'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Buat kunci di aistudio.google.com → Get API key, lalu tempel di sini.'),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                obscureText: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'AIza...'),
              ),
              if (result != null) ...[
                const SizedBox(height: 8),
                Text(result!, style: Theme.of(c).textTheme.bodySmall),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: testing
                  ? null
                  : () async {
                      setD(() => testing = true);
                      try {
                        await GeminiReader(
                          apiKey: ctrl.text.trim(),
                          model: s.aiModel.trim().isEmpty ? GeminiReader.defaultModel : s.aiModel.trim(),
                        ).ping();
                        result = 'Berhasil terhubung ✓';
                      } catch (e) {
                        result = 'Gagal: $e';
                      }
                      setD(() => testing = false);
                    },
              child: Text(testing ? 'Menguji...' : 'Uji'),
            ),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (r == null) return;
    await ref.read(settingsProvider.notifier).update(s.copyWith(aiKey: r, aiEnabled: r.isNotEmpty));
  }

  Future<void> _editModel(BuildContext context, WidgetRef ref) async {
    final s = ref.read(settingsProvider);
    final ctrl = TextEditingController(text: s.aiModel);
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Model Gemini'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: GeminiReader.defaultModel,
            helperText: 'Kosongkan untuk memakai model bawaan',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Simpan')),
        ],
      ),
    );
    ctrl.dispose();
    if (r == null) return;
    await ref.read(settingsProvider.notifier).update(s.copyWith(aiModel: r));
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
