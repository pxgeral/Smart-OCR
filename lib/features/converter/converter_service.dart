import 'dart:isolate';

import '../../models/converted_content.dart';
import '../../models/enums.dart';
import '../../models/ocr_result.dart';
import '../ocr/ocr_service.dart';
import 'page_analyzer.dart';
import 'page_assembler.dart';

class ConvertOptions {
  const ConvertOptions({
    this.force,
    this.cellOcr = true,
    this.dictionary = const [],
    this.keepOriginal = false,
  });

  /// true = isi dipakai persis seperti terbaca (tanpa koreksi otomatis).
  final bool keepOriginal;

  /// null = otomatis (tabel bila >= setengah halaman bertabel).
  final DocumentKind? force;

  /// OCR ulang tiap sel tabel (lebih lambat, jauh lebih akurat untuk
  /// tulisan tangan).
  final bool cellOcr;
  final List<String> dictionary;
}

class ConversionResult {
  const ConversionResult(this.content, this.ocr, this.pageImages,
      [this.warnings = const []]);
  final List<String> warnings;
  final ConvertedContent content;
  final OcrResult ocr;

  /// Gambar halaman ternormalisasi (koordinat OCR & sel mengacu ke sini).
  final List<String> pageImages;
}

/// Alur konversi per halaman:
/// 1. (Isolate) normalisasi gambar, deteksi tabel bergaris + warna,
///    potongan sel disusun menjadi mosaik.
/// 2. OCR halaman penuh + OCR mosaik (dua varian gambar).
/// 3. (Isolate) perakitan dokumen + verifikasi tulisan tangan.
class ConverterService {
  const ConverterService(this._ocr);
  final OcrService _ocr;

  Future<ConversionResult> convert(
    List<String> images, {
    required String workDir,
    ConvertOptions options = const ConvertOptions(),
    void Function(String message, double? progress)? onProgress,
  }) async {
    final pages = <AssemblyPage>[];
    final ocrPages = <OcrPage>[];
    final warnings = <String>[];
    final n = images.length;
    for (var i = 0; i < n; i++) {
      onProgress?.call('Menganalisis struktur halaman ${i + 1}/$n', i / n);
      final analysis = await _analyze(images[i], workDir, i, options.cellOcr);
      onProgress?.call('Membaca teks halaman ${i + 1}/$n', (i + 0.35) / n);
      final page = await _ocr.recognizeUncached(analysis.ocrPath, i);
      final mosA = <OcrPage>[], mosB = <OcrPage>[];
      final total = analysis.mosaicA.length;
      for (var m = 0; m < total; m++) {
        onProgress?.call(
            'Verifikasi tulisan tangan halaman ${i + 1}/$n (${m + 1}/$total)',
            (i + 0.45 + 0.5 * m / total) / n);
        mosA.add(await _safeOcr(analysis.mosaicA[m]));
        mosB.add(await _safeOcr(analysis.mosaicB[m]));
      }
      ocrPages.add(page);
      pages.add(AssemblyPage(analysis, page, mosA, mosB));
    }
    onProgress?.call('Memeriksa konsistensi isi tabel...', null);
    final content = await _assemble(
        pages, options.force, options.dictionary, options.keepOriginal);
    return ConversionResult(
      content,
      OcrResult(engine: OcrEngineId.mlkit, pages: ocrPages),
      [for (final p in pages) p.analysis.imagePath],
      warnings,
    );
  }

  Future<OcrPage> _safeOcr(String path) async {
    try {
      return await _ocr.recognizeUncached(path, 0);
    } catch (_) {
      return const OcrPage(index: 0, width: 0, height: 0, boxes: []);
    }
  }

  // Fungsi statis agar closure Isolate tidak ikut membawa `this`.
  static Future<PageAnalysis> _analyze(
          String path, String workDir, int index, bool cellOcr) =>
      Isolate.run(() => PageAnalyzer.analyze(
            sourcePath: path,
            workDir: workDir,
            pageIndex: index,
            detectTables: true,
            cellOcr: cellOcr,
          ));

  static Future<ConvertedContent> _assemble(List<AssemblyPage> pages,
          DocumentKind? force, List<String> dict, bool keepOriginal) =>
      Isolate.run(() => PageAssembler.assemble(pages,
          force: force, dictionary: dict, keepOriginal: keepOriginal));
}
