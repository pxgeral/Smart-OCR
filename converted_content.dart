import 'enums.dart';
import 'table_data.dart';

enum BlockType { paragraph, heading, bullet, numbered }

enum BlockAlign { left, center, right, justify }

class DocBlock {
  const DocBlock(
    this.text, {
    this.type = BlockType.paragraph,
    this.level = 1, // level heading 1-3
    this.align = BlockAlign.left,
  });

  final String text;
  final BlockType type;
  final int level;
  final BlockAlign align;
}

/// Kontrak keluaran Converter -> masukan Export (DOCX/XLSX/PDF/TXT).
class ConvertedContent {
  const ConvertedContent({
    required this.kind,
    this.blocks = const [],
    this.tables = const [],
  });

  final DocumentKind kind;
  final List<DocBlock> blocks;
  final List<TableData> tables;

  /// Teks polos untuk ekspor TXT.
  String get plainText => [
        ...blocks.map((b) => b.text),
        for (final t in tables) ...t.rows.map((r) => r.join('\t')),
      ].join('\n');
}
