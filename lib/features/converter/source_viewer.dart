import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/process_request.dart';
import '../../services/providers.dart';

/// Pratinjau berkas sumber (foto/PDF) sebelum dikonversi: geser antarhalaman,
/// cubit untuk memperbesar.
class SourceViewer extends ConsumerStatefulWidget {
  const SourceViewer({super.key, required this.request, this.initialPage = 0});
  final ProcessRequest request;
  final int initialPage;

  @override
  ConsumerState<SourceViewer> createState() => _SourceViewerState();
}

class _SourceViewerState extends ConsumerState<SourceViewer> {
  late final PageController _pc = PageController(initialPage: widget.initialPage);
  List<String>? _pages;
  Directory? _tmp;
  String _status = '';
  String? _error;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialPage;
    if (widget.request.isPdf) {
      _renderPdf();
    } else {
      _pages = widget.request.paths;
    }
  }

  Future<void> _renderPdf() async {
    try {
      final r = await ref.read(pdfRasterizerProvider).render(
            widget.request.paths.first,
            maxSide: 1800,
            onProgress: (d, t) {
              if (mounted) setState(() => _status = 'Menyiapkan halaman $d/$t');
            },
          );
      if (!mounted) {
        await r.dir.delete(recursive: true);
        return;
      }
      setState(() {
        _pages = r.paths;
        _tmp = r.dir;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'PDF tidak bisa dibuka: $e');
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    final d = _tmp;
    if (d != null) {
      d.delete(recursive: true).catchError((_) => d);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          pages == null || pages.isEmpty
              ? widget.request.name
              : 'Halaman ${_index + 1} / ${pages.length}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
          : pages == null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(_status, style: const TextStyle(color: Colors.white70)),
                  ]),
                )
              : PageView.builder(
                  controller: _pc,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => InteractiveViewer(
                    minScale: 1,
                    maxScale: 6,
                    child: Center(
                      child: Image.file(
                        File(pages[i]),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image, color: Colors.white54, size: 64),
                      ),
                    ),
                  ),
                ),
    );
  }
}
