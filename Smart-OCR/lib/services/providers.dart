import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/constants.dart';
import '../features/converter/converter_service.dart';
import '../features/export/export_service.dart';
import '../features/history/content_repository.dart';
import '../features/history/project_repository.dart';
import '../features/ocr/mlkit_ocr_engine.dart';
import '../features/ocr/ocr_service.dart';
import '../features/scanner/pdf_rasterizer.dart';
import '../features/scanner/scanner_service.dart';
import 'file_service.dart';
import 'thumbnail_service.dart';

/// Composition root: satu-satunya tempat dependensi dirakit.
final fileServiceProvider = Provider<FileService>((ref) => FileService());

final thumbnailServiceProvider = Provider<ThumbnailService>(
    (ref) => ThumbnailService(ref.watch(fileServiceProvider)));

final scannerServiceProvider = Provider<ScannerService>(
    (ref) => ScannerService(ref.watch(fileServiceProvider)));

final pdfRasterizerProvider = Provider<PdfRasterizer>(
    (ref) => PdfRasterizer(ref.watch(fileServiceProvider)));

final ocrServiceProvider = Provider<OcrService>((ref) {
  // Urutan prioritas mesin; tambahkan Paddle/Baidu/Tesseract di depan/belakang.
  final service = OcrService(
    [MlKitOcrEngine()],
    Hive.box<String>(AppConstants.ocrCacheBox),
  );
  ref.onDispose(service.dispose);
  return service;
});

final converterServiceProvider = Provider<ConverterService>(
    (ref) => ConverterService(ref.watch(ocrServiceProvider)));

final exportServiceProvider = Provider<ExportService>(
    (ref) => ExportService(ref.watch(fileServiceProvider)));

final projectRepositoryProvider = Provider<ProjectRepository>(
    (ref) => ProjectRepository(Hive.box<String>(AppConstants.projectsBox)));

final contentRepositoryProvider = Provider<ContentRepository>(
    (ref) => ContentRepository(Hive.box<String>(AppConstants.contentsBox)));
