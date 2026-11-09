# Smart OCR Converter

Foto / scan / PDF -> Word (.docx), Excel (.xlsx), PDF searchable, TXT.

## Build APK

### A. GitHub Actions (tanpa install apa pun)
1. Buat repo GitHub, unggah isi folder ini (termasuk `.github/`).
2. Tab **Actions** -> **Build APK** -> **Run workflow**.
3. Setelah hijau, unduh artifact **smart-ocr-converter-apk** (`app-release.apk`).

### B. Lokal
```bash
flutter create --platforms=android --org com.geral --project-name smart_ocr_converter .
# ubah minSdk ke 26 di android/app/build.gradle(.kts)
flutter pub get
flutter build apk --release --no-shrink
# hasil: build/app/outputs/flutter-apk/app-release.apk
```

## Struktur
```
lib/
  core/        constants, failure, result, format, zip_writer, xml_utils
  models/      enums, ocr_result, table_data, converted_content, project_item, process_request
  services/    providers (composition root), file_service, thumbnail_service
  features/
    scanner/   scanner_service (ML Kit), pdf_rasterizer, start_flow
    ocr/       ocr_engine (interface), mlkit_ocr_engine, ocr_service (cache+fallback), settings_screen
    converter/ layout_analyzer, table_detector, document_builder, converter_service, process_*
    export/    docx_exporter, xlsx_exporter, pdf_exporter, export_service
    history/   project_repository, projects_provider, history_screen
  widgets/     source_tab
```

## Menambah mesin OCR
Implement `OcrEngine` (`features/ocr/ocr_engine.dart`), lalu daftarkan di
`ocrServiceProvider` (`services/providers.dart`). Urutan list = prioritas + fallback.
