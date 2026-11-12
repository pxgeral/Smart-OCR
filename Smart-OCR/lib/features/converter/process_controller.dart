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

enum ProcessStep { idle, running, done, failed }

class ProcessState {
  const ProcessState({
    this.step = ProcessStep.idle,
    this.progress,
    this.message = '',
    this.project,
    this.content,
    this.preview = '',
    this.error = '',
  });

  final ProcessStep step;
  final double? progress; // null = indeterminate
  final String message, preview, error;
  final ProjectItem? project;
  final ConvertedContent? content;
}

/// Alur: (PDF -> gambar) -> analisis struktur -> OCR halaman & per sel ->
/// verifikasi -> ekspor -> simpan riwayat (termasuk data untuk ditinjau).
class ProcessController extends Notifier<ProcessState> {
  @override
  ProcessState build() => const ProcessState();

  void reset() {
    if (state.step != ProcessStep.running) state = const ProcessState();
  }

  void _progress(String message, [double? value]) => state = ProcessState(
      step: ProcessStep.running, message: message, progress: value);

  /// [choice] null = otomatis (tabel -> Excel, selain itu -> Word).
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
            ),
            onProgress: _progress,
          );
      final content = result.content;
      if (content.pages.every((p) => p.elements.isEmpty)) {
        throw const OcrFailure(
            'Teks tidak terdeteksi. Coba foto yang lebih jelas dan terang.');
      }

      // simpan gambar halaman untuk tinjauan & ekspor ulang
      final projDir = await files.subDir('projects/$id');
      final pageImages = <String>[];
      for (var i = 0; i < result.pageImages.length; i++) {
        final dst = '${projDir.path}/p${i + 1}.jpg';
        await File(result.pageImages[i]).copy(dst);
        pageImages.add(dst);
        if (i < content.pages.length) content.pages[i].imagePath = dst;
      }

      final type = choice ??
          (content.kind == DocumentKind.table
              ? OutputType.xlsx
              : OutputType.docx);
      _progress('Membuat file ${type.label}...');
      final file = await ref.read(exportServiceProvider).export(
            type: type,
            baseName: req.name,
            content: content,
            ocr: content.tables.isEmpty ? result.ocr : null,
            images: pageImages,
            options: ExportOptions.from(settings),
          );

      final thumb = pageImages.isEmpty
          ? ''
          : await ref.read(thumbnailServiceProvider).create(pageImages.first, id);
      final item = ProjectItem(
        id: id,
        name: req.name,
        createdAt: DateTime.now(),
        fileSource: req.paths.first,
        outputType: type,
        outputPath: file.path,
        thumbnail: thumb,
      );
      await ref.read(contentRepositoryProvider).save(id, content);
      await ref.read(projectsProvider.notifier).add(item);

      final text = content.plainText.replaceAll('\t', ' | ');
      state = ProcessState(
        step: ProcessStep.done,
        project: item,
        content: content,
        preview: text.length > 1500 ? '${text.substring(0, 1500)}...' : text,
      );
    } on Failure catch (f) {
      state = ProcessState(step: ProcessStep.failed, error: f.message);
    } catch (e) {
      state = ProcessState(
          step: ProcessStep.failed, error: 'Terjadi kesalahan: $e');
    } finally {
      for (final d in [tmp, work]) {
        try {
          await d?.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}

final processControllerProvider =
    NotifierProvider<ProcessController, ProcessState>(ProcessController.new);
