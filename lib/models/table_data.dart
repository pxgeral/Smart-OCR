/// Status verifikasi satu sel hasil OCR.
enum CellStatus {
  /// Terbaca konsisten / sudah dicek pengguna.
  ok,

  /// Dikoreksi otomatis atau beberapa hasil OCR berbeda: sebaiknya dicek.
  check,

  /// Tidak cocok dengan pola kolom / rumus / tidak terbaca: wajib dicek.
  error,

  /// Sudah diperiksa pengguna.
  verified,
}

enum CellAlign { left, center, right }

/// Satu sel tabel (bisa gabungan baris/kolom) beserta gaya dan posisinya
/// pada gambar sumber (px), agar bisa ditampilkan ulang saat verifikasi.
class TableCell {
  TableCell({
    required this.row,
    required this.col,
    this.rowSpan = 1,
    this.colSpan = 1,
    this.text = '',
    this.fill,
    this.fontColor,
    this.bold = false,
    this.align = CellAlign.left,
    this.numeric = false,
    this.status = CellStatus.ok,
    this.note = '',
    this.alternatives = const [],
    this.confidence = 1,
    this.box = const [0, 0, 0, 0],
    this.hasInk = false,
  });

  final int row, col, rowSpan, colSpan;
  String text;

  /// Warna latar RGB (0xRRGGBB) atau null bila putih/tanpa warna.
  int? fill;

  /// Warna tulisan RGB atau null (hitam).
  int? fontColor;
  bool bold;
  CellAlign align;

  /// Isi boleh ditulis sebagai angka di Excel.
  bool numeric;
  CellStatus status;
  String note;
  List<String> alternatives;
  double confidence;

  /// left, top, right, bottom (px pada gambar halaman).
  List<double> box;
  bool hasInk;

  bool get needsReview =>
      status == CellStatus.check || status == CellStatus.error;

  Map<String, dynamic> toMap() => {
        'r': row,
        'c': col,
        'rs': rowSpan,
        'cs': colSpan,
        't': text,
        if (fill != null) 'f': fill,
        if (fontColor != null) 'fc': fontColor,
        'b': bold,
        'a': align.index,
        'n': numeric,
        's': status.index,
        if (note.isNotEmpty) 'no': note,
        if (alternatives.isNotEmpty) 'alt': alternatives,
        'cf': confidence,
        'bx': box,
        'ink': hasInk,
      };

  factory TableCell.fromMap(Map<String, dynamic> m) => TableCell(
        row: m['r'] as int,
        col: m['c'] as int,
        rowSpan: m['rs'] as int? ?? 1,
        colSpan: m['cs'] as int? ?? 1,
        text: m['t'] as String? ?? '',
        fill: m['f'] as int?,
        fontColor: m['fc'] as int?,
        bold: m['b'] as bool? ?? false,
        align: CellAlign.values[(m['a'] as int? ?? 0)
            .clamp(0, CellAlign.values.length - 1)],
        numeric: m['n'] as bool? ?? false,
        status: CellStatus.values[(m['s'] as int? ?? 0)
            .clamp(0, CellStatus.values.length - 1)],
        note: m['no'] as String? ?? '',
        alternatives: [
          for (final a in (m['alt'] as List? ?? const [])) a.toString()
        ],
        confidence: (m['cf'] as num? ?? 1).toDouble(),
        box: [
          for (final v in (m['bx'] as List? ?? const [0, 0, 0, 0]))
            (v as num).toDouble()
        ],
        hasInk: m['ink'] as bool? ?? false,
      );
}

/// Tabel dengan struktur lengkap: lebar kolom, tinggi baris, sel gabungan,
/// warna, dan status verifikasi.
class TableData {
  TableData({
    required this.colWidths,
    required this.rowHeights,
    required this.cells,
    this.headerRows = 0,
    this.left = 0,
    this.top = 0,
    this.bodyFontPt = 10,
    this.headerFontPt = 10,
    this.ruled = true,
  });

  /// Tabel sederhana dari baris teks (mis. hasil deteksi tanpa garis).
  factory TableData.simple(List<List<String>> rows, {bool hasHeader = false}) {
    final n = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    return TableData(
      colWidths: List.filled(n == 0 ? 1 : n, 100),
      rowHeights: List.filled(rows.length, 30),
      headerRows: hasHeader && rows.isNotEmpty ? 1 : 0,
      ruled: true,
      cells: [
        for (var r = 0; r < rows.length; r++)
          for (var c = 0; c < n; c++)
            TableCell(
              row: r,
              col: c,
              text: c < rows[r].length ? rows[r][c] : '',
              bold: hasHeader && r == 0,
            ),
      ],
    );
  }

  /// Lebar tiap kolom & tinggi tiap baris dalam px gambar sumber.
  final List<double> colWidths, rowHeights;
  final List<TableCell> cells;
  int headerRows;

  /// Posisi pojok kiri-atas tabel pada gambar (px).
  final double left, top;
  double bodyFontPt, headerFontPt;

  /// false = tabel hasil tebakan tata letak (tanpa garis di sumber).
  final bool ruled;

  int get rowCount => rowHeights.length;
  int get columnCount => colWidths.length;
  double get width => colWidths.fold(0.0, (a, b) => a + b);
  double get height => rowHeights.fold(0.0, (a, b) => a + b);
  bool get hasHeader => headerRows > 0;

  /// Grid teks (sel gabungan ditulis di pojok kiri-atasnya).
  List<List<String>> get rows {
    final out = List.generate(rowCount, (_) => List.filled(columnCount, ''));
    for (final c in cells) {
      if (c.row < rowCount && c.col < columnCount) out[c.row][c.col] = c.text;
    }
    return out;
  }

  List<List<String>> get normalized => rows;

  TableCell? cellAt(int row, int col) {
    for (final c in cells) {
      if (row >= c.row &&
          row < c.row + c.rowSpan &&
          col >= c.col &&
          col < c.col + c.colSpan) {
        return c;
      }
    }
    return null;
  }

  Iterable<TableCell> get reviewCells => cells.where((c) => c.needsReview);

  Map<String, dynamic> toMap() => {
        'cw': colWidths,
        'rh': rowHeights,
        'cells': [for (final c in cells) c.toMap()],
        'hr': headerRows,
        'l': left,
        't': top,
        'bf': bodyFontPt,
        'hf': headerFontPt,
        'ru': ruled,
      };

  factory TableData.fromMap(Map<String, dynamic> m) {
    if (m.containsKey('rows')) {
      // format lama (v1.0)
      return TableData.simple(
        [
          for (final r in m['rows'] as List)
            [for (final c in r as List) c.toString()]
        ],
        hasHeader: m['header'] as bool? ?? false,
      );
    }
    List<double> d(String k) =>
        [for (final v in (m[k] as List? ?? const [])) (v as num).toDouble()];
    return TableData(
      colWidths: d('cw'),
      rowHeights: d('rh'),
      cells: [
        for (final c in m['cells'] as List)
          TableCell.fromMap(Map<String, dynamic>.from(c as Map))
      ],
      headerRows: m['hr'] as int? ?? 0,
      left: (m['l'] as num? ?? 0).toDouble(),
      top: (m['t'] as num? ?? 0).toDouble(),
      bodyFontPt: (m['bf'] as num? ?? 10).toDouble(),
      headerFontPt: (m['hf'] as num? ?? 10).toDouble(),
      ruled: m['ru'] as bool? ?? true,
    );
  }
}
