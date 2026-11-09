import '../../models/enums.dart';
import '../../models/ocr_result.dart';

/// Kontrak mesin OCR. Mesin baru (PaddleOCR, Baidu, Tesseract) cukup
/// implement ini lalu didaftarkan di providers.dart sesuai prioritas.
abstract interface class OcrEngine {
  OcrEngineId get id;
  Future<OcrPage> recognize(String imagePath, int pageIndex);
  Future<void> dispose();
}
