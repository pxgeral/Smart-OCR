/// Masukan satu proses konversi: gambar (1..n halaman) atau satu PDF.
class ProcessRequest {
  const ProcessRequest({
    required this.name,
    required this.paths,
    this.isPdf = false,
  });

  final String name;
  final List<String> paths;
  final bool isPdf;
}
