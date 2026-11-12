import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/process_request.dart';
import '../../services/providers.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(req.name, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Pages(request: req),
          const SizedBox(height: 16),
          Text('Hasil keluaran', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Otomatis'),
                selected: _choice == null,
                onSelected: running ? null : (_) => setState(() => _choice = null),
              ),
              for (final t in OutputType.values)
                ChoiceChip(
                  label: Text(t.label),
                  selected: _choice == t,
                  onSelected: running ? null : (_) => setState(() => _choice = t),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (s.step == ProcessStep.failed) ...[
            Text(s.error,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
          ],
          if (running) ...[
            LinearProgressIndicator(value: s.progress),
            const SizedBox(height: 8),
            Text(s.message),
          ] else if (s.step != ProcessStep.done)
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: Text(s.step == ProcessStep.failed
                  ? 'Coba lagi'
                  : 'Mulai Konversi'),
              onPressed: () => ref
                  .read(processControllerProvider.notifier)
                  .run(req, _choice),
            ),
          if (s.step == ProcessStep.done && s.project != null)
            _Result(state: s),
        ],
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

class _Result extends ConsumerWidget {
  const _Result({required this.state});
  final ProcessState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = state.project!;
    final files = ref.read(fileServiceProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(p.name),
              subtitle: Text('${p.outputType.label} (.${p.outputType.ext}) tersimpan di Riwayat'),
            ),
            if (state.content != null && state.content!.tables.isNotEmpty)
              _VerifySummary(state: state),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(child: SelectableText(state.preview)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VerifySummary extends StatelessWidget {
  const _VerifySummary({required this.state});
  final ProcessState state;

  @override
  Widget build(BuildContext context) {
    final c = state.content!;
    final tables = c.tables;
    final cells = tables.fold<int>(0, (n, t) => n + t.cells.where((x) => x.text.isNotEmpty).length);
    final review = c.reviewCount, errors = c.errorCount;
    final ok = review == 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: ok ? Colors.green.withValues(alpha: 0.10) : Colors.amber.withValues(alpha: 0.14),
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(ok ? Icons.verified : Icons.fact_check, color: ok ? Colors.green : Colors.amber.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ok
                        ? '${tables.length} tabel, $cells sel terisi. Semua konsisten.'
                        : '${tables.length} tabel, $cells sel terisi. $review sel perlu dicek'
                            '${errors > 0 ? ' ($errors wajib)' : ''}.',
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.rule),
                  label: Text(ok ? 'Lihat & koreksi tabel' : 'Tinjau sel yang meragukan'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ReviewScreen(project: state.project!),
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
