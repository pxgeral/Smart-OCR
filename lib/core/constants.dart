abstract final class AppConstants {
  static const appName = 'Smart OCR Converter';
  static const version = '1.6.0';

  // Hive boxes
  static const projectsBox = 'projects';
  static const ocrCacheBox = 'ocr_cache';
  static const contentsBox = 'contents';
  static const settingsBox = 'settings';

  // Batas
  static const maxPdfPages = 300;
  static const maxImageSide = 2800; // hindari mengecilkan scan A4 beresolusi tinggi
  static const jpegQuality = 95;
}
