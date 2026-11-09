import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../services/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
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
          subtitle: Text('Versi 1.0.0'),
        ),
      ],
    );
  }
}
