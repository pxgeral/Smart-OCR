class TableData {
  const TableData({required this.rows, this.hasHeader = true});

  final List<List<String>> rows;
  final bool hasHeader;

  int get columnCount =>
      rows.fold(0, (m, r) => r.length > m ? r.length : m);

  List<String> get header =>
      hasHeader && rows.isNotEmpty ? rows.first : const [];

  List<List<String>> get body =>
      hasHeader && rows.isNotEmpty ? rows.sublist(1) : rows;

  /// Semua baris diratakan ke jumlah kolom yang sama.
  List<List<String>> get normalized {
    final n = columnCount;
    return [
      for (final r in rows) [...r, ...List.filled(n - r.length, '')],
    ];
  }

  Map<String, dynamic> toMap() => {'rows': rows, 'header': hasHeader};

  factory TableData.fromMap(Map<String, dynamic> m) => TableData(
        rows: (m['rows'] as List)
            .map((r) => (r as List).map((c) => c.toString()).toList())
            .toList(),
        hasHeader: m['header'] as bool? ?? true,
      );
}
