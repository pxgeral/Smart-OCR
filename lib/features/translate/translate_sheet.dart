import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../../models/converted_content.dart';
import 'translation_service.dart';

class TranslateResult {
  const TranslateResult(this.content, this.language);
  final ConvertedContent content;
  final String language;
}

/// Pilih bahasa asal & tujuan lalu terjemahkan seluruh dokumen.
Future<TranslateResult?> showTranslateSheet(
    BuildContext context, ConvertedContent source) {
  return showModalBottomSheet<TranslateResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    builder: (_) => _TranslateSheet(source: source),
  );
}

class _TranslateSheet extends StatefulWidget {
  const _TranslateSheet({required this.source});
  final ConvertedContent source;

  @override
  State<_TranslateSheet> createState() => _TranslateSheetState();
}

class _TranslateSheetState extends State<_TranslateSheet> {
  final _service = TranslationService();
  TranslateLanguage _from = TranslateLanguage.indonesian;
  TranslateLanguage _to = TranslateLanguage.english;
  bool _busy = false;
  String _msg = '';
  double? _progress;
  String? _error;

  Future<void> _run() async {
    if (_from == _to) {
      setState(() => _error = 'Bahasa asal dan tujuan sama.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _msg = 'Menyiapkan...';
      _progress = null;
    });
    try {
      final out = await _service.translate(
        widget.source,
        from: _from,
        to: _to,
        onProgress: (m, p) {
          if (mounted) {
            setState(() {
              _msg = m;
              _progress = p;
            });
          }
        },
      );
      if (mounted) {
        Navigator.pop(context, TranslateResult(out, translateLanguages[_to] ?? _to.name));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Gagal menerjemahkan: $e';
        });
      }
    }
  }

  Widget _picker(String label, TranslateLanguage value, ValueChanged<TranslateLanguage> onChanged) =>
      DropdownButtonFormField<TranslateLanguage>(
        initialValue: value,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final e in translateLanguages.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: _busy ? null : (v) => v == null ? null : onChanged(v),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Terjemahkan dokumen', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Diterjemahkan di HP (Google ML Kit). Model tiap bahasa ±30 MB diunduh sekali saat '
            'pertama dipakai, setelahnya bisa offline. Angka, tanggal, dan struktur tabel tidak diubah.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _picker('Dari bahasa', _from, (v) => setState(() => _from = v)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _picker('Ke bahasa', _to, (v) => setState(() => _to = v))),
            IconButton(
              tooltip: 'Tukar',
              icon: const Icon(Icons.swap_vert),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        final t = _from;
                        _from = _to;
                        _to = t;
                      }),
            ),
          ]),
          const SizedBox(height: 16),
          if (_busy) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(_msg),
            const SizedBox(height: 8),
          ],
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
          ],
          Row(children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            const Spacer(),
            FilledButton.icon(
              icon: const Icon(Icons.translate),
              label: const Text('Terjemahkan'),
              onPressed: _busy ? null : _run,
            ),
          ]),
        ],
      ),
    );
  }
}
