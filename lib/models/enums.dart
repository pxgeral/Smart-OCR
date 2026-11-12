/// Hasil deteksi layout: tabel -> XLSX, dokumen -> DOCX.
enum DocumentKind { document, table }

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
