import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' hide TableCell;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../models/converted_content.dart';
import '../../models/enums.dart';
import '../../models/project_item.dart';
import '../../models/table_data.dart';
import '../../services/providers.dart';
import '../history/projects_provider.dart';

/// Layar verifikasi: tabel ditampilkan seperti aslinya, sel yang meragukan
/// ditandai (kuning = perlu cek, merah = wajib cek). Ketuk sel untuk melihat
/// potongan gambar aslinya dan memperbaiki isinya.
class ReviewScreen extends ConsumerStatefulWidget {
  /// Meninjau proyek yang sudah tersimpan di Riwayat.
  const ReviewScreen({super.key, required ProjectItem this.project})
      : content = null,
        initialType = null,
        onSaveNew = null;

  /// Pratinjau hasil yang BELUM disimpan: [onSaveNew] membuat file pertama.
  const ReviewScreen.pending({
    super.key,
    required ConvertedContent this.content,
    required OutputType this.initialType,
    required Future<ProjectItem> Function(OutputType type) this.onSaveNew,
  }) : project = null;

  final ProjectItem? project;
  final ConvertedContent? content;
  final OutputType? initialType;
  final Future<ProjectItem> Function(OutputType type)? onSaveNew;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  ConvertedContent? _content;
  late ProjectItem? _project = widget.project;
  OutputType get _type => _project?.outputType ?? widget.initialType ?? OutputType.xlsx;
  int _page = 0;
  int _section = 0; // indeks tabel; == jumlah tabel -> teks
  bool _dirty = false;
  bool _saving = false;
  final _crops = <TableCell, Uint8List?>{};

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _content = widget.content ?? (p == null ? null : ref.read(contentRepositoryProvider).load(p.id));
  }

  PageContent? get _pg {
    final c = _content;
    if (c == null || c.pages.isEmpty) return null;
    return c.pages[_page.clamp(0, c.pages.length - 1)];
  }

  List<TableData> get _tables => _pg?.tables.toList() ?? const [];

  @override
  Widget build(BuildContext context) {
    final c = _content;
    final scheme = Theme.of(context).colorScheme;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tinjau hasil')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Data tinjauan tidak tersedia untuk proyek ini '
              '(dibuat dengan versi lama). Konversi ulang dokumen untuk meninjau.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final review = c.reviewCount, errors = c.errorCount;
    final tables = _tables;
    final blocks = _pg?.blocks.toList() ?? const <DocBlock>[];
    final sections = [
      for (var i = 0; i < tables.length; i++) 'Tabel ${i + 1}',
      if (blocks.isNotEmpty) 'Teks',
    ];
    if (_section >= sections.length) _section = 0;

    return PopScope(
      canPop: !_dirty || widget.onSaveNew != null && _project == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_project == null ? 'Pratinjau hasil' : 'Tinjau hasil'),
          actions: [
            IconButton(
              tooltip: 'Sel berikutnya yang perlu dicek',
              icon: const Icon(Icons.skip_next),
              onPressed: review == 0 ? null : _nextReview,
            ),
            IconButton(
              tooltip: _project == null ? 'Simpan sebagai ${_type.label}' : 'Simpan & buat ulang file',
              icon: _saving
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              onPressed: _saving ? null : () => _save(_type),
            ),
            PopupMenuButton<OutputType>(
              tooltip: 'Ekspor ke format lain',
              icon: const Icon(Icons.ios_share),
              onSelected: _save,
              itemBuilder: (_) => [
                for (final t in OutputType.values)
                  PopupMenuItem(value: t, child: Text('Simpan sebagai ${t.label}')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Material(
              color: review == 0 ? Colors.green.withValues(alpha: 0.12) : scheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    Icon(review == 0 ? Icons.verified : Icons.fact_check,
                        color: review == 0 ? Colors.green : scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(review == 0
                          ? 'Semua sel sudah konsisten / diperiksa.'
                          : '$review sel perlu dicek'
                              '${errors > 0 ? ' ($errors wajib)' : ''}. Ketuk sel bertanda.'),
                    ),
                  ],
                ),
              ),
            ),
            if (c.pages.length > 1)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    for (var i = 0; i < c.pages.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('Hal ${i + 1}${_pageBadge(c.pages[i])}'),
                          selected: i == _page,
                          onSelected: (_) => setState(() {
                            _page = i;
                            _section = 0;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            if (sections.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SegmentedButton<int>(
                  segments: [
                    for (var i = 0; i < sections.length; i++)
                      ButtonSegment(value: i, label: Text(sections[i])),
                  ],
                  selected: {_section},
                  onSelectionChanged: (s) => setState(() => _section = s.first),
                ),
              ),
            const _Legend(),
            Expanded(
              child: sections.isEmpty
                  ? const Center(child: Text('Halaman kosong'))
                  : _section < tables.length
                      ? TablePreview(
                          key: ValueKey('t$_page-$_section'),
                          table: tables[_section],
                          onTap: (cell) => _edit(tables[_section], cell),
                        )
                      : _TextList(
                          blocks: blocks,
                          onEdit: _editBlock,
                        ),
            ),
          ],
        ),
      ),
    );
  }

  String _pageBadge(PageContent p) {
    final n = p.tables.fold<int>(0, (s, t) => s + t.reviewCells.length);
    return n == 0 ? '' : ' • $n';
  }

  Future<bool> _confirmLeave() async {
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Simpan perubahan?'),
        content: const Text('Perubahan belum dimasukkan ke file hasil.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: const Text('Buang')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Simpan')),
        ],
      ),
    );
    if (r == 'save') {
      await _save(_type);
      return true;
    }
    return r == 'discard';
  }

  Future<void> _save(OutputType type) async {
    final c = _content;
    if (c == null) return;
    setState(() => _saving = true);
    try {
      final cur = _project;
      final saved = cur == null
          ? await widget.onSaveNew!(type)
          : await ref.read(projectsProvider.notifier).saveAndExport(cur, c, type);
      _project = saved;
      _dirty = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('File ${type.label} diperbarui'),
        action: SnackBarAction(
          label: 'Buka',
          onPressed: () => ref.read(fileServiceProvider).open(saved.outputPath),
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _nextReview() {
    final c = _content;
    if (c == null) return;
    // mulai dari posisi sekarang, lanjut ke halaman berikutnya
    for (var k = 0; k < c.pages.length; k++) {
      final pi = (_page + k) % c.pages.length;
      final tables = c.pages[pi].tables.toList();
      for (var ti = 0; ti < tables.length; ti++) {
        final cells = tables[ti].reviewCells.toList()
          ..sort((a, b) => a.row != b.row ? a.row.compareTo(b.row) : a.col.compareTo(b.col));
        if (cells.isEmpty) continue;
        setState(() {
          _page = pi;
          _section = ti;
        });
        _edit(tables[ti], cells.first);
        return;
      }
    }
  }

  Future<Uint8List?> _crop(TableCell cell) async {
    if (_crops.containsKey(cell)) return _crops[cell];
    final path = _pg?.imagePath ?? '';
    if (path.isEmpty || cell.box.length != 4 || !File(path).existsSync()) return null;
    final box = cell.box;
    final bytes = await _cropAsync(path, box);
    _crops[cell] = bytes;
    return bytes;
  }

  Future<void> _edit(TableData table, TableCell cell) async {
    final saved = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CellEditor(
        cell: cell,
        crop: _crop(cell),
        hasNext: (_content?.reviewCount ?? 0) > (cell.needsReview ? 1 : 0),
      ),
    );
    if (saved == null) return;
    setState(() {
      cell.text = saved.text;
      cell.status = CellStatus.verified;
      cell.note = '';
      final num = RegExp(r'^-?\d+(\.\d+)?$').hasMatch(saved.text.trim());
      final colNumeric = table.cells.any((c) => c.col == cell.col && c.numeric && c != cell);
      cell.numeric = num && (cell.numeric || colNumeric);
      _dirty = true;
    });
    if (saved.next) _nextReview();
  }

  Future<void> _editBlock(DocBlock b) async {
    final ctrl = TextEditingController(text: b.text);
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit teks'),
        content: TextField(controller: ctrl, maxLines: null, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Simpan')),
        ],
      ),
    );
    ctrl.dispose();
    if (r == null) return;
    setState(() {
      b.text = r;
      _dirty = true;
    });
  }
}

Future<Uint8List?> _cropAsync(String path, List<double> box) =>
    Isolate.run(() => _cropImage(path, box));

Uint8List? _cropImage(String path, List<double> box) {
  final src = img.decodeImage(File(path).readAsBytesSync());
  if (src == null) return null;
  final w = box[2] - box[0], h = box[3] - box[1];
  final mx = math.max(w * 0.25, 24.0), my = math.max(h * 0.6, 24.0);
  final x0 = (box[0] - mx).floor().clamp(0, src.width - 1);
  final y0 = (box[1] - my).floor().clamp(0, src.height - 1);
  final x1 = (box[2] + mx).ceil().clamp(x0 + 1, src.width);
  final y1 = (box[3] + my).ceil().clamp(y0 + 1, src.height);
  final crop = img.copyCrop(src, x: x0, y: y0, width: x1 - x0, height: y1 - y0);
  // bingkai merah di sekitar sel yang sedang diedit
  img.drawRect(crop,
      x1: (box[0] - x0).round(),
      y1: (box[1] - y0).round(),
      x2: (box[2] - x0).round(),
      y2: (box[3] - y0).round(),
      color: img.ColorRgb8(229, 57, 53),
      thickness: 3);
  return img.encodeJpg(crop, quality: 90);
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(border: Border.all(color: c, width: 2.5))),
          const SizedBox(width: 4),
          Text(t, style: Theme.of(context).textTheme.labelSmall),
        ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(spacing: 14, runSpacing: 4, children: [
        item(Colors.red, 'Wajib cek'),
        item(Colors.amber.shade700, 'Perlu cek'),
        item(Colors.green, 'Sudah diperiksa'),
      ]),
    );
  }
}

/// Tabel seperti aslinya (warna, sel gabungan, tanda status); bisa digeser &
/// diperbesar.
class TablePreview extends StatelessWidget {
  const TablePreview({super.key, required this.table, this.onTap});
  final TableData table;
  final void Function(TableCell cell)? onTap;

  @override
  Widget build(BuildContext context) {
    final t = table;
    if (t.columnCount == 0 || t.rowCount == 0) return const SizedBox();
    final ws = [...t.colWidths]..sort();
    final med = ws[ws.length ~/ 2];
    final s = med <= 0 ? 1.0 : 76 / med;
    final xs = <double>[0];
    for (final w in t.colWidths) {
      xs.add(xs.last + math.max(36, w * s));
    }
    final ys = <double>[0];
    for (final h in t.rowHeights) {
      ys.add(ys.last + math.max(30, h * s));
    }
    return InteractiveViewer(
      constrained: false,
      minScale: 0.3,
      maxScale: 4,
      boundaryMargin: const EdgeInsets.all(200),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: xs.last,
          height: ys.last,
          child: Stack(
            children: [
              for (final c in t.cells)
                if (c.row < t.rowCount && c.col < t.columnCount)
                  Positioned(
                    left: xs[c.col],
                    top: ys[c.row],
                    width: xs[math.min(c.col + c.colSpan, t.columnCount)] - xs[c.col],
                    height: ys[math.min(c.row + c.rowSpan, t.rowCount)] - ys[c.row],
                    child: _CellBox(
                      cell: c,
                      header: c.row < t.headerRows,
                      onTap: onTap == null ? null : () => onTap!(c),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CellBox extends StatelessWidget {
  const _CellBox({required this.cell, required this.header, this.onTap});
  final TableCell cell;
  final bool header;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = cell.fill == null ? Colors.white : Color(0xFF000000 | cell.fill!);
    final Color? mark = switch (cell.status) {
      CellStatus.error => Colors.red,
      CellStatus.check => Colors.amber.shade700,
      CellStatus.verified => Colors.green,
      CellStatus.ok => null,
    };
    final dark = fill.computeLuminance() < 0.35;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: Colors.black54, width: 0.5),
        ),
        foregroundDecoration: mark == null
            ? null
            : BoxDecoration(border: Border.all(color: mark, width: cell.status == CellStatus.verified ? 1.5 : 2.5)),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        alignment: header
            ? Alignment.center
            : switch (cell.align) {
                CellAlign.center => Alignment.center,
                CellAlign.right => Alignment.centerRight,
                CellAlign.left => Alignment.centerLeft,
              },
        child: Text(
          cell.text,
          textAlign: header ? TextAlign.center : TextAlign.start,
          overflow: TextOverflow.fade,
          style: TextStyle(
            fontSize: header ? 10 : 13,
            fontWeight: header || cell.bold ? FontWeight.bold : FontWeight.normal,
            color: cell.fontColor != null
                ? Color(0xFF000000 | cell.fontColor!)
                : (dark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }
}

class _TextList extends StatelessWidget {
  const _TextList({required this.blocks, required this.onEdit});
  final List<DocBlock> blocks;
  final void Function(DocBlock b) onEdit;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: blocks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final b = blocks[i];
        return ListTile(
          title: Text(b.text,
              style: TextStyle(fontWeight: b.bold ? FontWeight.bold : FontWeight.normal)),
          tileColor: b.fill == null ? null : Color(0xFF000000 | b.fill!).withValues(alpha: 0.25),
          trailing: const Icon(Icons.edit, size: 18),
          onTap: () => onEdit(b),
        );
      },
    );
  }
}

class _EditResult {
  const _EditResult(this.text, this.next);
  final String text;
  final bool next;
}

class _CellEditor extends StatefulWidget {
  const _CellEditor({required this.cell, required this.crop, required this.hasNext});
  final TableCell cell;
  final Future<Uint8List?> crop;
  final bool hasNext;

  @override
  State<_CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<_CellEditor> {
  late final _ctrl = TextEditingController(text: widget.cell.text);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Baris ${cell.row + 1}, kolom ${cell.col + 1}', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder<Uint8List?>(
            future: widget.crop,
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(height: 90, child: Center(child: CircularProgressIndicator()));
              }
              final b = snap.data;
              if (b == null) return const SizedBox.shrink();
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Image.memory(b, height: 140, fit: BoxFit.contain, gaplessPlayback: true),
                ),
              );
            },
          ),
          if (cell.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(cell.status == CellStatus.error ? Icons.error : Icons.info_outline,
                  size: 18,
                  color: cell.status == CellStatus.error ? Colors.red : Colors.amber.shade800),
              const SizedBox(width: 6),
              Expanded(child: Text(cell.note, style: theme.textTheme.bodySmall)),
            ]),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: null,
            decoration: const InputDecoration(
              labelText: 'Isi sel',
              border: OutlineInputBorder(),
            ),
          ),
          if (cell.alternatives.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Bacaan lain:', style: theme.textTheme.labelMedium),
            Wrap(
              spacing: 6,
              children: [
                for (final a in cell.alternatives.take(6))
                  ActionChip(label: Text(a), onPressed: () => _ctrl.text = a),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(onPressed: () => _ctrl.clear(), child: const Text('Kosongkan')),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, _EditResult(_ctrl.text.trim(), false)),
                child: const Text('Simpan'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, _EditResult(_ctrl.text.trim(), widget.hasNext)),
                child: Text(widget.hasNext ? 'Benar, lanjut' : 'Benar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
