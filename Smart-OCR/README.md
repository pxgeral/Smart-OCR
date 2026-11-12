# Smart OCR Converter

Aplikasi Flutter untuk mengubah hasil scan, foto, dan PDF menjadi dokumen Word (`.docx`), Excel (`.xlsx`), PDF searchable, atau teks. OCR berjalan di perangkat menggunakan Google ML Kit. Aplikasi juga menyimpan riwayat konversi secara lokal.

## Fitur

- Memindai dokumen melalui kamera dengan deteksi tepi dan koreksi perspektif.
- Memilih gambar dari galeri atau PDF untuk OCR.
- Mengarahkan hasil tabel ke Excel dan dokumen biasa ke Word; format keluaran juga dapat dipilih di alur konversi.
- Mengekspor PDF searchable, DOCX, XLSX, dan TXT.
- Menyimpan riwayat, hasil terstruktur, dan gambar halaman agar bisa ditinjau & diekspor ulang.

### Baru di 1.1

**Hasil menyerupai dokumen asli**

- Deteksi struktur tabel bergaris: garis gelap, garis putih di kepala berwarna, dan tepi warna; tahan terhadap foto yang sedikit miring/perspektif.
- Sel gabungan (rowspan/colspan) dikenali dan dipertahankan di Excel (`mergeCells`) dan Word (`gridSpan`/`vMerge`).
- Warna latar sel, pita judul berwarna, warna tinta, perataan teks, tebal kepala tabel, ukuran huruf, lebar kolom dan tinggi baris proporsional.
- Teks di luar tabel (judul, subjudul, tanda tangan) ditempatkan sesuai urutan halaman; orientasi halaman (potret/lanskap) dipertahankan.
- Tanda air "Dipindai dengan CamScanner" dibuang. Paket DOCX/XLSX dikompres (DEFLATE).

**Verifikasi tulisan tangan**

- Setiap sel bertinta dipotong dan dibaca ulang (varian warna asli + varian kontras dinormalisasi) lewat mosaik, lalu dibandingkan dengan OCR halaman penuh.
- Pola kolom dikenali otomatis (jam, desimal, bilangan bulat, teks) untuk memperbaiki salah baca umum (O→0, S→5, l→1, `0555`→`05.55`, dll.).
- Pemeriksaan rentang nilai per kolom dan rumus antarkolom (mis. kolom "Rata-rata" = rata-rata kolom di kirinya); bila ada bacaan alternatif yang membuat rumus cocok, bacaan itu dipakai.
- Ejaan kata yang berulang diseragamkan (mis. "Nesi" → "Nasi"), plus kamus kata dari Pengaturan.
- Layar **Tinjau hasil**: sel kuning (perlu cek) / merah (wajib cek), ketuk untuk melihat potongan gambar asli, pilih bacaan lain atau ketik koreksi, lalu file dibuat ulang.
- Excel mendapat lembar **Verifikasi** berisi daftar sel yang perlu dicek dengan tautan langsung.

OCR berjalan lokal dengan model Latin Google ML Kit. Tulisan tangan yang sangat samar tetap bisa keliru, karena itu sel yang meragukan selalu ditandai untuk ditinjau.

## Build APK lokal

Persyaratan: Flutter stable yang memenuhi batas SDK di `pubspec.yaml`, JDK 21, dan Android SDK yang diterima melalui `flutter doctor --android-licenses`. Paket Android memakai `minSdk` 26.

```bash
flutter doctor
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release
```

APK release berada di `build/app/outputs/flutter-apk/app-release.apk`.

## Build melalui GitHub Actions

Workflow **Build APK** berjalan saat dipanggil manual dari tab **Actions** atau ketika kode aplikasi/build berubah di branch `main` atau `master`. Unduh artifact `smart-ocr-converter-apk` setelah workflow selesai.

## Struktur sumber

```text
lib/
  core/        konstanta, error, format, utilitas XML/ZIP
  models/      model OCR, dokumen, proyek, dan permintaan proses
  services/    dependency providers dan layanan berkas/thumbnail
  features/
    scanner/   kamera, PDF ke gambar, dan pemilihan sumber
    ocr/       engine ML Kit, cache OCR, dan pengaturan
    converter/ struktur tabel (table_structure), analisis halaman & mosaik
               (page_analyzer), perakitan (page_assembler), verifikasi
               tulisan tangan (cell_verifier), alur konversi
    review/    layar tinjau & koreksi sel
    export/    ekspor DOCX, XLSX, PDF searchable, dan TXT
    history/   penyimpanan dan tampilan riwayat
  widgets/     komponen UI bersama
```

## Menambah mesin OCR

Implementasikan `OcrEngine` di `lib/features/ocr/ocr_engine.dart`, lalu daftarkan engine di `ocrServiceProvider` pada `lib/services/providers.dart`. Urutan daftar menentukan prioritas dan fallback.
