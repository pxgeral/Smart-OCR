import 'dart:io';

import 'package:flutter/material.dart' hide TableCell;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/process_request.dart';
import '../../services/providers.dart';
import '../../services/settings_provider.dart';
import '../review/review_screen.dart';
import 'process_controller.dart';

class ProcessScreen extends ConsumerStatefulWidget {
  const ProcessScreen({super.key, required this.request});
  final ProcessRequest request;

  @override
  ConsumerState<ProcessScreen> createState() => _ProcessScreenState();
}

class _ProcessScreenState extends ConsumerState<ProcessScreen> {
  OutputType? _choice; // null = otomatis

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(processControllerProvider.notifier).reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(processControllerProvider);
    final running = s.step == ProcessStep.running;
    final req = widget.request;
    final ai = ref.watch(settingsProvider).aiReady;

    return Scaffold(
      appBar: AppBar(
        title: Text(req.name, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Pages(request: req),
          const SizedBox(height: 16),
          if (s.step == ProcessStep.idle || s.step == ProcessStep.failed || running && s.content == null) ...[
            Text('Hasil keluaran', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _FormatChips(
              value: _choice,
              allowAuto: true,
              enabled: !running,
              onChanged: (v) => setState(() => _choice = v),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Icon(ai ? Icons.auto_awesome : Icons.offline_bolt, size: 16,
                  color: ai ? Colors.deepPurple : Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ai
                      ? 'AI Gemini aktif: isi tabel juga dibaca AI (perlu internet).'
                      : 'Mode offline (ML Kit). AI Gemini bisa diaktifkan di Pengaturan.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ]),
            const SizedBox(height: 16),
          ],
          if (s.step == ProcessStep.failed) ...[
            Text(s.error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
          ],
          if (running) ...[
            LinearProgressIndicator(value: s.progress),
            const SizedBox(height: 8),
            Text(s.message),
          ] else if (s.step == ProcessStep.idle || s.step == ProcessStep.failed)
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: Text(s.step == ProcessStep.failed ? 'Coba lagi' : 'Baca & pratinjau'),
              onPressed: () => ref.read(processControllerProvider.notifier).run(req, _choice),
            ),
          if (!running && (s.step == ProcessStep.preview || s.step == ProcessStep.done) && s.content != null)
            _Preview(state: s),
        ],
      ),
    );
  }
}

class _FormatChips extends StatelessWidget {
  const _FormatChips({
    required this.value,
    required this.onChanged,
    this.allowAuto = false,
    this.enabled = true,
  });
  final OutputType? value;
  final bool allowAuto, enabled;
  final ValueChanged<OutputType?> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        children: [
          if (allowAuto)
            ChoiceChip(
              label: const Text('Otomatis'),
              selected: value == null,
              onSelected: enabled ? (_) => onChanged(null) : null,
            ),
          for (final t in OutputType.values)
            ChoiceChip(
              label: Text(t.label),
              selected: value == t,
              onSelected: enabled ? (_) => onChanged(t) : null,
            ),
        ],
      );
}

/// Pratinjau sebelum file dibuat: ringkasan, cuplikan tabel seperti aslinya,
/// tombol periksa/koreksi, lalu pilih format dan simpan.
class _Preview extends ConsumerStatefulWidget {
  const _Preview({required this.state});
  final ProcessState state;

  @override
  ConsumerState<_Preview> createState() => _PreviewState();
}

class _PreviewState extends ConsumerState<_Preview> {
  OutputType? _type;
  int _table = 0;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = s.content!;
    final type = _type ?? s.project?.outputType ?? s.suggested ?? OutputType.xlsx;
    final tables = c.tables;
    final cells = tables.fold<int>(0, (n, t) => n + t.cells.where((x) => x.text.isNotEmpty).length);
    final review = c.reviewCount, errors = c.errorCount;
    final ctrl = ref.read(processControllerProvider.notifier);
    final done = s.step == ProcessStep.done && s.project != null;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          color: review == 0 ? Colors.green.withValues(alpha: 0.10) : Colors.amber.withValues(alpha: 0.14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(review == 0 ? Icons.verified : Icons.fact_check,
                  color: review == 0 ? Colors.green : Colors.amber.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tables.isEmpty
                    ? '${c.pages.length} halaman, ${c.blocks.length} paragraf teks.'
                    : '${c.pages.length} halaman, ${tables.length} tabel, $cells sel terisi.'
                        '${review > 0 ? ' $review sel perlu dicek${errors > 0 ? ' ($errors wajib)' : ''}.' : ' Semua konsisten.'}'),
              ),
            ]),
          ),
        ),
        for (final w in s.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('⚠ $w', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Text('Pratinjau', style: theme.textTheme.titleSmall),
          const Spacer(),
          if (tables.length > 1)
            DropdownButton<int>(
              value: _table.clamp(0, tables.length - 1),
              items: [
                for (var i = 0; i < tables.length; i++)
                  DropdownMenuItem(value: i, child: Text('Tabel ${i + 1}')),
              ],
              onChanged: (v) => setState(() => _table = v ?? 0),
            ),
        ]),
        const SizedBox(height: 6),
        Container(
          height: 320,
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: tables.isEmpty
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(c.plainText.length > 3000 ? '${c.plainText.substring(0, 3000)}...' : c.plainText),
                )
              : TablePreview(
                  key: ValueKey('pv$_table-${c.hashCode}'),
                  table: tables[_table.clamp(0, tables.length - 1)],
                ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.rule),
          label: Text(review > 0 ? 'Periksa & koreksi ($review sel ragu)' : 'Periksa & edit isi'),
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => s.project != null
                  ? ReviewScreen(project: s.project!)
                  : ReviewScreen.pending(
                      content: c,
                      initialType: type,
                      onSaveNew: ctrl.finalize,
                    ),
            ));
            ctrl.touch();
          },
        ),
        const SizedBox(height: 16),
        Text('Simpan sebagai', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        _FormatChips(value: type, onChanged: (v) => setState(() => _type = v)),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_alt),
          label: Text(done && type == s.project!.outputType
              ? 'Perbarui file ${type.label}'
              : 'Buat file ${type.label}'),
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await ctrl.finalize(type);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e')));
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
        ),
        if (done) ...[
          const SizedBox(height: 12),
          _Saved(state: s),
        ],
      ],
    );
  }
}

class _Saved extends ConsumerWidget {
  const _Saved({required this.state});
  final ProcessState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = state.project!;
    final files = ref.read(fileServiceProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: Text(p.name),
            subtitle: Text('${p.outputType.label} (.${p.outputType.ext}) tersimpan di Riwayat'),
          ),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('Buka'),
                onPressed: () => files.open(p.outputPath),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('Bagikan'),
                onPressed: () => files.share(p.outputPath),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Pages extends StatelessWidget {
  const _Pages({required this.request});
  final ProcessRequest request;

  @override
  Widget build(BuildContext context) {
    if (request.isPdf) {
      return const ListTile(
        leading: Icon(Icons.picture_as_pdf, size: 40),
        title: Text('Dokumen PDF'),
        subtitle: Text('Halaman dibaca otomatis (maks. 300 halaman)'),
        contentPadding: EdgeInsets.zero,
      );
    }
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: request.paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(request.paths[i]),
            height: 110,
            cacheWidth: 240, // lazy + hemat memori
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const SizedBox(width: 80, child: Icon(Icons.broken_image)),
          ),
        ),
      ),
    );
  }
}

