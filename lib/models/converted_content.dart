import 'enums.dart';
import 'table_data.dart';

enum BlockType { paragraph, heading, bullet, numbered }

enum BlockAlign { left, center, right, justify }

class DocBlock {
  DocBlock(
    this.text, {
    this.type = BlockType.paragraph,
    this.level = 1, // level heading 1-3
    this.align = BlockAlign.left,
    this.fontPt = 0, // 0 = ukuran bawaan
    this.bold = false,
    this.fill,
    this.fontColor,
    this.top = 0,
    this.left = 0,
    this.right = 0,
    this.bottom = 0,
  });

  String text;
  final BlockType type;
  final int level;
  final BlockAlign align;
  final double fontPt;
  final bool bold;

  /// Warna latar (mis. pita judul berwarna), RGB 0xRRGGBB.
  final int? fill;
  final int? fontColor;

  /// Posisi pada gambar sumber (px).
  final double top, left, right, bottom;

  Map<String, dynamic> toMap() => {
        't': text,
        'ty': type.index,
        'lv': level,
        'al': align.index,
        'fp': fontPt,
        'b': bold,
        if (fill != null) 'f': fill,
        if (fontColor != null) 'fc': fontColor,
        'bx': [left, top, right, bottom],
      };

  factory DocBlock.fromMap(Map<String, dynamic> m) {
    final bx = [
      for (final v in (m['bx'] as List? ?? const [0, 0, 0, 0]))
        (v as num).toDouble()
    ];
    return DocBlock(
      m['t'] as String? ?? '',
      type: BlockType.values[m['ty'] as int? ?? 0],
      level: m['lv'] as int? ?? 1,
      align: BlockAlign.values[m['al'] as int? ?? 0],
      fontPt: (m['fp'] as num? ?? 0).toDouble(),
      bold: m['b'] as bool? ?? false,
      fill: m['f'] as int?,
      fontColor: m['fc'] as int?,
      left: bx[0],
      top: bx[1],
      right: bx[2],
      bottom: bx[3],
    );
  }
}

/// Elemen halaman berurutan dari atas ke bawah: paragraf atau tabel.
sealed class PageElement {
  const PageElement();
  double get top;
  double get left;
  double get right;
  double get bottom;

  Map<String, dynamic> toMap();

  static PageElement fromMap(Map<String, dynamic> m) => m['k'] == 'tbl'
      ? TableElement(TableData.fromMap(Map<String, dynamic>.from(m['v'] as Map)))
      : TextElement(DocBlock.fromMap(Map<String, dynamic>.from(m['v'] as Map)));
}

final class TextElement extends PageElement {
  const TextElement(this.block);
  final DocBlock block;
  @override
  double get top => block.top;
  @override
  double get left => block.left;
  @override
  double get right => block.right;
  @override
  double get bottom => block.bottom;
  @override
  Map<String, dynamic> toMap() => {'k': 'txt', 'v': block.toMap()};
}

final class TableElement extends PageElement {
  const TableElement(this.table);
  final TableData table;
  @override
  double get top => table.top;
  @override
  double get left => table.left;
  @override
  double get right => table.left + table.width;
  @override
  double get bottom => table.top + table.height;
  @override
  Map<String, dynamic> toMap() => {'k': 'tbl', 'v': table.toMap()};
}

/// Satu halaman sumber: ukuran gambar (px) dan elemennya.
class PageContent {
  PageContent({
    required this.width,
    required this.height,
    required this.elements,
    this.imagePath = '',
  });

  final double width, height;
  final List<PageElement> elements;

  /// Gambar halaman tersimpan (untuk potongan sel saat verifikasi).
  String imagePath;

  bool get landscape => width > height;

  Iterable<TableData> get tables =>
      elements.whereType<TableElement>().map((e) => e.table);

  Iterable<DocBlock> get blocks =>
      elements.whereType<TextElement>().map((e) => e.block);

  Map<String, dynamic> toMap() => {
        'w': width,
        'h': height,
        'img': imagePath,
        'el': [for (final e in elements) e.toMap()],
      };

  factory PageContent.fromMap(Map<String, dynamic> m) => PageContent(
        width: (m['w'] as num).toDouble(),
        height: (m['h'] as num).toDouble(),
        imagePath: m['img'] as String? ?? '',
        elements: [
          for (final e in m['el'] as List)
            PageElement.fromMap(Map<String, dynamic>.from(e as Map))
        ],
      );
}

/// Kontrak keluaran Converter -> masukan Export (DOCX/XLSX/PDF/TXT).
class ConvertedContent {
  ConvertedContent({required this.kind, required this.pages});

  final DocumentKind kind;
  final List<PageContent> pages;

  List<DocBlock> get blocks => [for (final p in pages) ...p.blocks];
  List<TableData> get tables => [for (final p in pages) ...p.tables];

  int get reviewCount =>
      tables.fold(0, (n, t) => n + t.reviewCells.length);

  int get errorCount => tables.fold(
      0, (n, t) => n + t.cells.where((c) => c.status == CellStatus.error).length);

  /// Teks polos untuk ekspor TXT, urut sesuai halaman.
  String get plainText {
    final sb = StringBuffer();
    for (var i = 0; i < pages.length; i++) {
      if (i > 0) sb.writeln();
      for (final e in pages[i].elements) {
        switch (e) {
          case TextElement(:final block):
            sb.writeln(block.text);
          case TableElement(:final table):
            for (final r in table.rows) {
              sb.writeln(r.join('\t'));
            }
            sb.writeln();
        }
      }
    }
    return sb.toString().trimRight();
  }

  Map<String, dynamic> toMap() => {
        'v': 2,
        'kind': kind.name,
        'pages': [for (final p in pages) p.toMap()],
      };

  factory ConvertedContent.fromMap(Map<String, dynamic> m) => ConvertedContent(
        kind: DocumentKind.values.byName(m['kind'] as String),
        pages: [
          for (final p in m['pages'] as List)
            PageContent.fromMap(Map<String, dynamic>.from(p as Map))
        ],
      );
}
