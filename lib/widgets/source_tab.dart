import 'package:flutter/material.dart';

/// Halaman sumber (Kamera / Galeri / PDF): ikon, penjelasan, satu tombol.
class SourceTab extends StatefulWidget {
  const SourceTab({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onStart,
  });

  final IconData icon;
  final String title, subtitle, buttonLabel;
  final Future<void> Function() onStart;

  @override
  State<SourceTab> createState() => _SourceTabState();
}

class _SourceTabState extends State<SourceTab> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await widget.onStart();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(widget.subtitle,
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(widget.icon),
              label: Text(widget.buttonLabel),
              onPressed: _busy ? null : _go,
            ),
          ],
        ),
      ),
    );
  }
}
