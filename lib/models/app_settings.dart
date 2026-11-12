class AppSettings {
  const AppSettings({
    this.cellOcr = true,
    this.keepColors = true,
    this.reviewSheet = true,
    this.markInExcel = false,
    this.dictionary = const [],
    this.aiEnabled = false,
    this.aiKey = '',
    this.aiModel = '',
  });

  /// Bantuan AI Gemini (online) untuk membaca isi sel.
  final bool aiEnabled;
  final String aiKey;

  /// Kosong = model bawaan (gemini-flash-latest).
  final String aiModel;

  bool get aiReady => aiEnabled && aiKey.trim().isNotEmpty;

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
    bool? aiEnabled,
    String? aiKey,
    String? aiModel,
  }) =>
      AppSettings(
        cellOcr: cellOcr ?? this.cellOcr,
        keepColors: keepColors ?? this.keepColors,
        reviewSheet: reviewSheet ?? this.reviewSheet,
        markInExcel: markInExcel ?? this.markInExcel,
        dictionary: dictionary ?? this.dictionary,
        aiEnabled: aiEnabled ?? this.aiEnabled,
        aiKey: aiKey ?? this.aiKey,
        aiModel: aiModel ?? this.aiModel,
      );

  Map<String, dynamic> toMap() => {
        'cellOcr': cellOcr,
        'keepColors': keepColors,
        'reviewSheet': reviewSheet,
        'markInExcel': markInExcel,
        'dictionary': dictionary,
        'aiEnabled': aiEnabled,
        'aiKey': aiKey,
        'aiModel': aiModel,
      };

  factory AppSettings.fromMap(Map<String, dynamic> m) => AppSettings(
        cellOcr: m['cellOcr'] as bool? ?? true,
        keepColors: m['keepColors'] as bool? ?? true,
        reviewSheet: m['reviewSheet'] as bool? ?? true,
        markInExcel: m['markInExcel'] as bool? ?? false,
        dictionary: [
          for (final w in (m['dictionary'] as List? ?? const [])) w.toString()
        ],
        aiEnabled: m['aiEnabled'] as bool? ?? false,
        aiKey: m['aiKey'] as String? ?? '',
        aiModel: m['aiModel'] as String? ?? '',
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
