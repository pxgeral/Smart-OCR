String _two(int n) => n.toString().padLeft(2, '0');

/// 20261108_213500 (untuk nama file)
String stamp(DateTime d) =>
    '${d.year}${_two(d.month)}${_two(d.day)}_${_two(d.hour)}${_two(d.minute)}${_two(d.second)}';

/// 08/11/2026 21:35 (untuk tampilan)
String displayDate(DateTime d) =>
    '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

String stripExt(String name) {
  final i = name.lastIndexOf('.');
  return i > 0 ? name.substring(0, i) : name;
}
