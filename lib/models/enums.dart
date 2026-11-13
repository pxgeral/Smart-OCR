/// Hasil deteksi layout: tabel -> XLSX, dokumen -> DOCX.
enum DocumentKind { document, table }

/// Cara memperlakukan isi dokumen saat dibaca.
enum ResultMode {
  /// Rapikan & koreksi otomatis (angka, jam, tanggal, ejaan, rumus).
  edit('Ubah & rapikan',
      'Kesalahan baca dikoreksi otomatis (O→0, jam, tanggal, ejaan, rumus rata-rata).'),

  /// Teks dipakai persis seperti terbaca; sel meragukan tetap ditandai.
  original('Seperti aslinya',
      'Isi dipertahankan persis seperti terbaca, tanpa koreksi otomatis. '
      'Sel yang meragukan tetap ditandai untuk dicek.');

  const ResultMode(this.label, this.hint);
  final String label, hint;
}

enum OutputType {
  docx('Word', 'docx'),
  xlsx('Excel', 'xlsx'),
  pdf('PDF', 'pdf'),
  txt('TXT', 'txt');

  const OutputType(this.label, this.ext);
  final String label;
  final String ext;
}

/// Urutan prioritas dikelola oleh OcrService.
enum OcrEngineId { paddle, baidu, mlkit, tesseract }
