class AppSettings {
  const AppSettings({
    this.cellOcr = true,
    this.keepColors = true,
    this.reviewSheet = true,
    this.markInExcel = false,
    this.dictionary = const [],
  });

  /// OCR ulang per sel untuk tulisan tangan.
  final bool cellOcr;

  /// Pertahankan warna sel & pita judul di Word/Excel.
  final bool keepColors;

  /// Tambah lembar "Verifikasi" berisi daftar sel yang perlu dicek.
  final bool reviewSheet;

  /// Beri tanda warna pada sel yang perlu dicek di Excel/Word.
  final bool markInExcel;

  /// Kata tambahan untuk koreksi ejaan (nama menu, nama orang, dsb.).
  final List<String> dictionary;

  AppSettings copyWith({
    bool? cellOcr,
    bool? keepColors,
    bool? reviewSheet,
    bool? markInExcel,
    List<String>? dictionary,
  }) =>
      AppSettings(
        cellOcr: cellOcr ?? this.cellOcr,
        keepColors: keepColors ?? this.keepColors,
        reviewSheet: reviewSheet ?? this.reviewSheet,
        markInExcel: markInExcel ?? this.markInExcel,
        dictionary: dictionary ?? this.dictionary,
      );

  Map<String, dynamic> toMap() => {
        'cellOcr': cellOcr,
        'keepColors': keepColors,
        'reviewSheet': reviewSheet,
        'markInExcel': markInExcel,
        'dictionary': dictionary,
      };

  factory AppSettings.fromMap(Map<String, dynamic> m) => AppSettings(
        cellOcr: m['cellOcr'] as bool? ?? true,
        keepColors: m['keepColors'] as bool? ?? true,
        reviewSheet: m['reviewSheet'] as bool? ?? true,
        markInExcel: m['markInExcel'] as bool? ?? false,
        dictionary: [
          for (final w in (m['dictionary'] as List? ?? const [])) w.toString()
        ],
      );
}

/// Opsi yang memengaruhi berkas keluaran.
class ExportOptions {
  const ExportOptions({
    this.keepColors = true,
    this.reviewSheet = true,
    this.markReview = false,
  });

  factory ExportOptions.from(AppSettings s) => ExportOptions(
      keepColors: s.keepColors,
      reviewSheet: s.reviewSheet,
      markReview: s.markInExcel);

  final bool keepColors, reviewSheet, markReview;
}
