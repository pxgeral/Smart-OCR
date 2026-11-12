import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

/// ZIP minimal untuk paket DOCX/XLSX (DEFLATE; STORE bila tidak lebih kecil).
class ZipWriter {
  final _entries = <_Entry>[];

  void addString(String name, String content) =>
      addBytes(name, utf8.encode(content));

  void addBytes(String name, List<int> data) =>
      _entries.add(_Entry(utf8.encode(name), Uint8List.fromList(data)));

  Uint8List build() {
    final out = BytesBuilder();
    final central = BytesBuilder();
    for (final e in _entries) {
      final offset = out.length;
      final crc = _crc32(e.data);
      final size = e.data.length;
      var method = 0;
      List<int> payload = e.data;
      if (size > 64) {
        final z = ZLibEncoder(raw: true, level: 6).convert(e.data);
        if (z.length < size) {
          method = 8;
          payload = z;
        }
      }
      final csize = payload.length;

      final local = ByteData(30)
        ..setUint32(0, 0x04034b50, Endian.little)
        ..setUint16(4, 20, Endian.little) // versi minimum
        ..setUint16(6, 0x0800, Endian.little) // nama file UTF-8
        ..setUint16(8, method, Endian.little) // 0 = store, 8 = deflate
        ..setUint16(10, 0, Endian.little) // jam
        ..setUint16(12, 0x21, Endian.little) // tanggal 1980-01-01
        ..setUint32(14, crc, Endian.little)
        ..setUint32(18, csize, Endian.little)
        ..setUint32(22, size, Endian.little)
        ..setUint16(26, e.name.length, Endian.little)
        ..setUint16(28, 0, Endian.little);
      out
        ..add(local.buffer.asUint8List())
        ..add(e.name)
        ..add(payload);

      final c = ByteData(46)
        ..setUint32(0, 0x02014b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 20, Endian.little)
        ..setUint16(8, 0x0800, Endian.little)
        ..setUint16(10, method, Endian.little)
        ..setUint16(12, 0, Endian.little)
        ..setUint16(14, 0x21, Endian.little)
        ..setUint32(16, crc, Endian.little)
        ..setUint32(20, csize, Endian.little)
        ..setUint32(24, size, Endian.little)
        ..setUint16(28, e.name.length, Endian.little)
        ..setUint16(30, 0, Endian.little) // extra
        ..setUint16(32, 0, Endian.little) // komentar
        ..setUint16(34, 0, Endian.little) // disk
        ..setUint16(36, 0, Endian.little) // atribut internal
        ..setUint32(38, 0, Endian.little) // atribut eksternal
        ..setUint32(42, offset, Endian.little);
      central
        ..add(c.buffer.asUint8List())
        ..add(e.name);
    }

    final cdOffset = out.length;
    final cdSize = central.length;
    out.add(central.toBytes());
    final end = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(4, 0, Endian.little)
      ..setUint16(6, 0, Endian.little)
      ..setUint16(8, _entries.length, Endian.little)
      ..setUint16(10, _entries.length, Endian.little)
      ..setUint32(12, cdSize, Endian.little)
      ..setUint32(16, cdOffset, Endian.little)
      ..setUint16(20, 0, Endian.little);
    out.add(end.buffer.asUint8List());
    return out.toBytes();
  }
}

class _Entry {
  _Entry(this.name, this.data);
  final List<int> name;
  final Uint8List data;
}

final List<int> _table = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
