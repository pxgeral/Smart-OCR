import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/failure.dart';
import '../../core/format.dart';
import '../../core/result.dart';
import '../../models/process_request.dart';
import '../../services/file_service.dart';

/// Semua metode: Ok(null) = pengguna membatalkan.
class ScannerService {
  ScannerService(this._files);
  final FileService _files;

  /// Auto crop, deteksi tepi, perspektif, rotate, filter, multi-halaman
  /// ditangani Google ML Kit Document Scanner (Android, perlu Play Services).
  Future<Result<ProcessRequest?>> scanWithCamera() async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: {DocumentFormat.jpeg},
        mode: ScannerMode.filter,
        pageLimit: 30,
        isGalleryImport: false,
      ),
    );
    try {
      final r = await scanner.scanDocument();
      final paths = List<String>.from(r.images ?? const <String>[]);
      if (paths.isEmpty) return const Ok(null);
      return Ok(ProcessRequest(name: 'Scan ${stamp(DateTime.now())}', paths: paths));
    } catch (e) {
      if (e.toString().toLowerCase().contains('cancel')) return const Ok(null);
      return Err(ScanFailure('Scanner gagal ($e). Coba tab Galeri.'));
    } finally {
      scanner.close();
    }
  }

  /// Pilih beberapa foto; otomatis diperkecil & dikompres.
  Future<Result<ProcessRequest?>> pickImages() async {
    try {
      final files = await ImagePicker().pickMultiImage(
        maxWidth: AppConstants.maxImageSide.toDouble(),
        maxHeight: AppConstants.maxImageSide.toDouble(),
        imageQuality: AppConstants.jpegQuality,
      );
      if (files.isEmpty) return const Ok(null);
      return Ok(ProcessRequest(
        name: 'Foto ${stamp(DateTime.now())}',
        paths: [for (final f in files) f.path],
      ));
    } catch (e) {
      return Err(ScanFailure('Gagal membuka galeri: $e'));
    }
  }

  Future<Result<ProcessRequest?>> pickPdf() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (files == null || files.isEmpty) return const Ok(null);
      final f = files.first;
      // Salin ke cache agar bisa dibaca sebagai path biasa.
      final dir = await _files.subDir('pdf_in', temp: true);
      final out = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.pdf');
      await out.writeAsBytes(await f.readAsBytes());
      return Ok(ProcessRequest(name: stripExt(f.name), paths: [out.path], isPdf: true));
    } catch (e) {
      return Err(ScanFailure('Gagal membuka PDF: $e'));
    }
  }
}
