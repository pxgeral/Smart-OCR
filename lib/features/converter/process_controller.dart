import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../models/app_settings.dart';
import '../../models/converted_content.dart';
import '../../models/enums.dart';
import '../../models/process_request.dart';
import '../../models/project_item.dart';
import '../../services/providers.dart';
import '../../services/settings_provider.dart';
import '../history/projects_provider.dart';
import 'converter_service.dart';

enum ProcessStep { idle, running, preview, done, failed }

class ProcessState {
  const ProcessState({
    this.step = ProcessStep.idle,
    this.progress,
    this.message = '',
    this.project,
    this.content,
    this.suggested,
    this.warnings = const [],
    this.error = '',
  });

  final ProcessStep step;
  final double? progress; // null = indeterminate
  final String message, error;
  final ProjectItem? project;
  final ConvertedContent? content;

  /// Format keluaran yang disarankan (tabel -> Excel, dokumen -> Word).
  final OutputType? suggested;
  final List<String> warnings;
}

/// Alur: (PDF -> gambar) -> analisis struktur -> OCR halaman & per sel
/// (+ AI opsional) -> verifikasi -> PRATINJAU -> ekspor -> riwayat.
class ProcessController extends Notifier<ProcessState> {
  @override
  ProcessState build() => const ProcessState();

  // data hasil analisis yang menunggu disimpan
  ProcessRequest? _req;
  ConversionResult? _result;
  List<String> _pageImages = const [];
  String _id = '';

  void reset() {
    if (state.step != ProcessStep.running) {
      state = const ProcessState();
      _req = null;
      _result = null;
    }
  }

  void _progress(String message, [double? value]) => state = ProcessState(
      step: ProcessStep.running, message: message, progress: value);

  /// Analisis & baca dokumen, lalu berhenti di pratinjau.
  /// [choice] null = otomatis.
  Future<void> run(ProcessRequest req, OutputType? choice) async {
    if (state.step == ProcessStep.running) return;
    _progress('Menyiapkan halaman...');
    final files = ref.read(fileServiceProvider);
    final settings = ref.read(settingsProvider);
    Directory? tmp;
    Directory? work;
    try {
      var images = req.paths;
      if (req.isPdf) {
        final r = await ref.read(pdfRasterizerProvider).render(
              req.paths.first,
              onProgress: (d, t) => _progress('Membaca PDF $d/$t', d / t),
            );
        images = r.paths;
        tmp = r.dir;
      }
      if (images.isEmpty) {
        throw const ConversionFailure('Tidak ada halaman yang bisa dibaca.');
      }

      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final workBase = await files.subDir('work', temp: true);
      work = await Directory('${workBase.path}/$id').create(recursive: true);

      final result = await ref.read(converterServiceProvider).convert(
            images,
            workDir: work.path,
            options: ConvertOptions(
              force: choice == OutputType.xlsx ? DocumentKind.table : null,
              cellOcr: settings.cellOcr,
              dictionary: settings.dictionary,
              aiKey: settings.aiReady ? settings.aiKey : '',
              aiModel: settings.aiModel,
            ),
            onProgress: _progress,
          );
      final content = result.content;
      if (content.pages.every((p) => p.elements.isEmpty)) {
        throw const OcrFailure(
            'Teks tidak terdeteksi. Coba foto yang lebih jelas dan terang.');
      }

      // simpan gambar halaman (untuk pratinjau, tinjauan & ekspor ulang)
      final projDir = await files.subDir('projects/$id');
      final pageImages = <String>[];
      for (var i = 0; i < result.pageImages.length; i++) {
        final dst = '${projDir.path}/p${i + 1}.jpg';
        await File(result.pageImages[i]).copy(dst);
        pageImages.add(dst);
        if (i < content.pages.length) content.pages[i].imagePath = dst;
      }

      _req = req;
      _result = result;
      _pageImages = pageImages;
      _id = id;
      state = ProcessState(
        step: ProcessStep.preview,
        content: content,
        suggested: choice ??
            (content.kind == DocumentKind.table ? OutputType.xlsx : OutputType.docx),
        warnings: result.warnings,
      );
    } on Failure catch (f) {
      state = ProcessState(step: ProcessStep.failed, error: f.message);
    } catch (e) {
      state = ProcessState(step: ProcessStep.failed, error: 'Terjadi kesalahan: $e');
    } finally {
      for (final d in [tmp, work]) {
        try {
          await d?.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Buat file dari hasil pratinjau (isi mungkin sudah dikoreksi pengguna)
  /// dan simpan ke Riwayat. Pemanggilan berikutnya memperbarui proyek yang sama.
  Future<ProjectItem> finalize(OutputType type) async {
    final existing = state.project;
    final content = state.content;
    if (content == null) throw StateError('Tidak ada hasil untuk disimpan');
    if (existing != null) {
      final n = await ref.read(projectsProvider.notifier).saveAndExport(existing, content, type);
      state = ProcessState(step: ProcessStep.done, project: n, content: content, suggested: type);
      return n;
    }
    final req = _req, result = _result;
    if (req == null || result == null) throw StateError('Tidak ada hasil untuk disimpan');
    final settings = ref.read(settingsProvider);
    final prev = state;
    state = ProcessState(
        step: ProcessStep.running, message: 'Membuat file ${type.label}...', content: content);
    try {
      final file = await ref.read(exportServiceProvider).export(
            type: type,
            baseName: req.name,
            content: content,
            ocr: content.tables.isEmpty ? result.ocr : null,
            images: _pageImages,
            options: ExportOptions.from(settings),
          );
      final thumb = _pageImages.isEmpty
          ? ''
          : await ref.read(thumbnailServiceProvider).create(_pageImages.first, _id);
      final item = ProjectItem(
        id: _id,
        name: req.name,
        createdAt: DateTime.now(),
        fileSource: req.paths.first,
        outputType: type,
        outputPath: file.path,
        thumbnail: thumb,
      );
      await ref.read(contentRepositoryProvider).save(_id, content);
      await ref.read(projectsProvider.notifier).add(item);
      state = ProcessState(
          step: ProcessStep.done, project: item, content: content, suggested: type,
          warnings: prev.warnings);
      return item;
    } catch (e) {
      state = prev;
      rethrow;
    }
  }

  /// Dipanggil layar pratinjau setelah isi diedit (memicu tampilan ulang).
  void touch() {
    state = ProcessState(
      step: state.step,
      content: state.content,
      project: state.project,
      suggested: state.suggested,
      warnings: state.warnings,
    );
  }
}

final processControllerProvider =
    NotifierProvider<ProcessController, ProcessState>(ProcessController.new);
