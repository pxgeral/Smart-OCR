import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/failure.dart';
import '../../models/enums.dart';
import '../../models/process_request.dart';
import '../../models/project_item.dart';
import '../../services/providers.dart';
import '../history/projects_provider.dart';

enum ProcessStep { idle, running, done, failed }

class ProcessState {
  const ProcessState({
    this.step = ProcessStep.idle,
    this.progress,
    this.message = '',
    this.project,
    this.preview = '',
    this.error = '',
  });

  final ProcessStep step;
  final double? progress; // null = indeterminate
  final String message, preview, error;
  final ProjectItem? project;
}

/// Alur: (PDF -> gambar) -> OCR -> konversi -> ekspor -> simpan riwayat.
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
    Directory? tmp;
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

      final ocr = await ref.read(ocrServiceProvider).recognizeAll(
            images,
            onProgress: (d, t) => _progress('OCR halaman $d/$t', d / t),
          );
      if (ocr.isEmpty) {
        throw const OcrFailure(
            'Teks tidak terdeteksi. Coba foto yang lebih jelas dan terang.');
      }

      _progress('Menganalisis struktur dokumen...');
      final content = await ref.read(converterServiceProvider).convert(
            ocr,
            force: choice == OutputType.xlsx ? DocumentKind.table : null,
          );
      final type = choice ??
          (content.kind == DocumentKind.table
              ? OutputType.xlsx
              : OutputType.docx);

      _progress('Membuat file ${type.label}...');
      final file = await ref.read(exportServiceProvider).export(
            type: type,
            baseName: req.name,
            content: content,
            ocr: ocr,
            images: images,
          );

      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final thumb =
          await ref.read(thumbnailServiceProvider).create(images.first, id);
      final item = ProjectItem(
        id: id,
        name: req.name,
        createdAt: DateTime.now(),
        fileSource: req.paths.first,
        outputType: type,
        outputPath: file.path,
        thumbnail: thumb,
      );
      await ref.read(projectsProvider.notifier).add(item);

      final text = content.plainText.replaceAll('\t', ' | ');
      state = ProcessState(
        step: ProcessStep.done,
        project: item,
        preview: text.length > 1500 ? '${text.substring(0, 1500)}...' : text,
      );
    } on Failure catch (f) {
      state = ProcessState(step: ProcessStep.failed, error: f.message);
    } catch (e) {
      state = ProcessState(
          step: ProcessStep.failed, error: 'Terjadi kesalahan: $e');
    } finally {
      try {
        await tmp?.delete(recursive: true);
      } catch (_) {}
    }
  }
}

final processControllerProvider =
    NotifierProvider<ProcessController, ProcessState>(ProcessController.new);
