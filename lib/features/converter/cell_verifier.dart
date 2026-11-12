import 'dart:math' as math;

import '../../models/table_data.dart';

/// Satu kandidat bacaan OCR untuk sebuah sel.
class OcrCandidate {
  const OcrCandidate(this.text, this.confidence, this.source);
  final String text;
  final double confidence;

  /// 'page' = OCR halaman penuh, 'crop' = potongan sel warna asli,
  /// 'norm' = potongan sel kontras dinormalisasi,
  /// 'box' = kotak centang.
  final String source;
}

enum ColumnKind { empty, text, integer, decimal, time, date }

class ColumnProfile {
  ColumnProfile(this.kind,
      {this.intDigits = 0,
      this.fracDigits = 0,
      this.sep = '.',
      this.decSep = '.',
      this.header = ''});
  final ColumnKind kind;
  final int intDigits, fracDigits;
  final String sep;

  /// Pemisah desimal yang dipakai di kolom ("," gaya Indonesia atau ".").
  final String decSep;
  final String header;
  double median = 0, spread = 0;
  int valid = 0;

  bool get numeric => kind == ColumnKind.decimal || kind == ColumnKind.integer;
}

/// Tabel + kandidat OCR per sel yang akan diverifikasi.
class VerifyTable {
  VerifyTable(this.table, this.candidates);
  final TableData table;
  final Map<TableCell, List<OcrCandidate>> candidates;
}

class _Fix {
  const _Fix(this.value, this.valid, this.changed);
  final String value;
  final bool valid, changed;
}

/// Verifikasi tulisan tangan: memilih bacaan terbaik dari beberapa hasil OCR,
/// mengoreksi berdasar pola kolom (jam, desimal, angka), mengecek rentang
/// nilai & rumus rata-rata/jumlah antarkolom, dan menyeragamkan ejaan kata
/// yang berulang. Sel yang meragukan diberi status agar dicek pengguna.
abstract final class CellVerifier {
  static final _letters = RegExp(r'[A-Za-z]');
  static final _digits = RegExp(r'\d');
  static final _timeRe = RegExp(r'^(\d{1,2})[.:,](\d{2})$');
  static final _decRe = RegExp(r'^-?\d{1,7}([.,]\d{1,4})?$');
  static final _intRe = RegExp(r'^-?\d{1,12}$');
  static final _timeHeader =
      RegExp(r'waktu|jam|pukul|time|mulai|selesai|tiba|berangkat', caseSensitive: false);

  /// Kata dasar yang sering muncul di formulir (ditambah kamus pengguna).
  static const builtInWords = [
    'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu',
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli',
    'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  static void verify(List<VerifyTable> tables, {List<String> dictionary = const []}) {
    final profiles = <VerifyTable, List<ColumnProfile>>{};
    for (final vt in tables) {
      final p = _profiles(vt);
      profiles[vt] = p;
      _choose(vt, p);
      _rangeCheck(vt, p);
      _relations(vt, p);
    }
    _vocabulary(tables, profiles, [...builtInWords, ...dictionary]);
  }

  // ------------------------------------------------------------ helpers

  static String clean(String s) {
    var t = s
        .replaceAll(RegExp(r'[·•∙●]'), '.')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
    t = t.replaceAll(RegExp(r'^[|_~]+|[|_~]+$'), '').trim();
    return t;
  }

  static const _confusions = {
    'O': '0', 'o': '0', 'D': '0', 'Q': '0', 'U': '0', 'u': '0',
    'I': '1', 'l': '1', '|': '1', 'i': '1', '!': '1', ']': '1', '[': '1',
    'J': '1', 'j': '1', 'L': '1', 'f': '1', 't': '1',
    'Z': '2', 'z': '2',
    'A': '4', 'h': '4', 'y': '4',
    'S': '5', 's': '5', r'$': '5',
    'G': '6', 'b': '6',
    'T': '7', '?': '7',
    'B': '8', '&': '8',
    'g': '9', 'q': '9', 'P': '9', 'p': '9',
  };

  static bool numericish(String s) {
    final t = s.replaceAll(RegExp(r'[\s.,:;\-]'), '');
    if (t.isEmpty) return false;
    final d = _digits.allMatches(t).length;
    if (d == 0) return false;
    final letters = _letters.allMatches(t).length;
    // kata (mis. "Batch 2") bukan angka
    if (letters >= 3 && letters > d) return false;
    var conf = 0;
    for (final ch in t.split('')) {
      if (_confusions.containsKey(ch)) conf++;
    }
    return (d + conf) / t.length >= 0.75 && d >= (t.length / 2).floor();
  }

  static String _mapDigits(String s) {
    final sb = StringBuffer();
    for (final ch in s.split('')) {
      sb.write(_confusions[ch] ?? ch);
    }
    return sb.toString();
  }

  static _Fix _fixValue(String raw, ColumnProfile p) {
    final c = clean(raw);
    if (c.isEmpty) return const _Fix('', true, false);
    switch (p.kind) {
      case ColumnKind.empty:
      case ColumnKind.text:
        return _Fix(c, true, false);
      case ColumnKind.date:
        return _fixDate(c, p);
      case ColumnKind.integer:
      case ColumnKind.decimal:
      case ColumnKind.time:
        if (!numericish(c)) return _Fix(c, false, false);
    }
    var t = _mapDigits(c).replaceAll(' ', '');
    // pemisah apa pun di antara angka -> titik
    t = t.replaceAll(RegExp(r'[,:;\-_' "'" r'`]'), '.');
    t = t.replaceAll(RegExp(r'[^0-9.]'), '');
    t = t.replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (t.isEmpty) return _Fix(c, false, false);

    switch (p.kind) {
      case ColumnKind.time:
        final d = t.replaceAll('.', '');
        if (d.length < 3 || d.length > 4) return _Fix(c, false, t != c);
        final hh = int.parse(d.substring(0, d.length - 2));
        final mm = int.parse(d.substring(d.length - 2));
        if (hh > 23 || mm > 59) return _Fix(c, false, true);
        final v = '${hh.toString().padLeft(2, '0')}${p.sep}${mm.toString().padLeft(2, '0')}';
        return _Fix(v, true, v != c);
      case ColumnKind.decimal:
        if ('.'.allMatches(t).length > 1) {
          final digits = t.replaceAll('.', '');
          t = p.fracDigits > 0 && digits.length > p.fracDigits
              ? '${digits.substring(0, digits.length - p.fracDigits)}.${digits.substring(digits.length - p.fracDigits)}'
              : digits;
        } else if (!t.contains('.') &&
            p.fracDigits > 0 &&
            p.intDigits > 0 &&
            t.length == p.intDigits + p.fracDigits) {
          t = '${t.substring(0, p.intDigits)}.${t.substring(p.intDigits)}';
        }
        final out = p.decSep == ',' ? t.replaceAll('.', ',') : t;
        return _Fix(out, _decRe.hasMatch(t), out != c);
      case ColumnKind.integer:
        final v = t.replaceAll('.', '');
        return _Fix(v, _intRe.hasMatch(v), v != c);
      case ColumnKind.empty:
      case ColumnKind.text:
      case ColumnKind.date:
        return _Fix(c, true, false);
    }
  }

  static final _dateRe = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})$');

  /// Tanggal: "04/03/2025". Garis miring sering terbaca "1"/"l"/"7"
  /// ("0410312025"), diperbaiki dari posisi pemisahnya.
  static _Fix _fixDate(String c, ColumnProfile p) {
    var t = c.replaceAll(' ', '');
    // huruf mirip angka (tanpa menyentuh pemisah)
    t = t.split('').map((ch) => const {'O': '0', 'o': '0', 'D': '0', 'S': '5', 's': '5', 'B': '8', 'Z': '2', 'z': '2', 'g': '9', 'q': '9', 'G': '6', 'b': '6'}[ch] ?? ch).join();
    String? d, m, y;
    final mm = _dateRe.firstMatch(t.replaceAll(RegExp(r'[\\|]'), '/'));
    if (mm != null) {
      d = mm.group(1);
      m = mm.group(2);
      y = mm.group(3);
    } else {
      final digits = t.replaceAll(RegExp(r'[Il|]'), '1');
      final sepLike = RegExp(r'^(\d{2})[17/](\d{2})[17/](\d{4})$').firstMatch(digits);
      final plain = RegExp(r'^(\d{2})(\d{2})(\d{4})$').firstMatch(digits);
      final hit = sepLike ?? plain;
      if (hit != null) {
        d = hit.group(1);
        m = hit.group(2);
        y = hit.group(3);
      }
    }
    if (d == null || m == null || y == null) return _Fix(c, false, false);
    final di = int.parse(d), mi = int.parse(m);
    if (di < 1 || di > 31 || mi < 1 || mi > 12) return _Fix(c, false, true);
    final v = '${d.padLeft(2, '0')}${p.sep}${m.padLeft(2, '0')}${p.sep}$y';
    return _Fix(v, true, v != c);
  }

  static String _headerOf(TableData t, int col) {
    final parts = <String>[];
    for (final c in t.cells) {
      if (c.row < t.headerRows && col >= c.col && col < c.col + c.colSpan) {
        if (c.text.trim().isNotEmpty) parts.add(c.text.trim());
      }
    }
    return parts.join(' ');
  }

  static OcrCandidate? _bestRaw(List<OcrCandidate> cands) {
    OcrCandidate? best;
    for (final c in cands) {
      if (clean(c.text).isEmpty) continue;
      if (best == null || c.confidence > best.confidence) best = c;
    }
    return best;
  }

  static int _mode(List<int> v) {
    if (v.isEmpty) return 0;
    final m = <int, int>{};
    for (final x in v) {
      m[x] = (m[x] ?? 0) + 1;
    }
    return m.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static String _modeStr(List<String> v) {
    final m = <String, int>{};
    for (final x in v) {
      m[x] = (m[x] ?? 0) + 1;
    }
    return m.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static List<ColumnProfile> _profiles(VerifyTable vt) {
    final t = vt.table;
    final out = <ColumnProfile>[];
    for (var col = 0; col < t.columnCount; col++) {
      final header = _headerOf(t, col);
      final samples = <String>[];
      for (final cell in t.cells) {
        if (cell.col != col || cell.colSpan != 1 || cell.row < t.headerRows) {
          continue;
        }
        final best = _bestRaw(vt.candidates[cell] ?? const []);
        if (best != null) samples.add(clean(best.text));
      }
      if (samples.length < 2) {
        out.add(ColumnProfile(
            samples.isEmpty ? ColumnKind.empty : ColumnKind.text,
            header: header));
        continue;
      }
      var time = 0, dec = 0, integer = 0, numCount = 0, dates = 0, commas = 0;
      final intD = <int>[], fracD = <int>[], seps = <String>[], dateSeps = <String>[];
      for (final s in samples) {
        final df = _fixDate(s, ColumnProfile(ColumnKind.date, sep: '/'));
        if (df.valid) {
          dates++;
          final sm = RegExp(r'\d([/\-.])\d').firstMatch(s);
          dateSeps.add(sm?.group(1) ?? '/');
          continue;
        }
        if (!numericish(s)) continue;
        numCount++;
        final m0 = _mapDigits(s).replaceAll(' ', '');
        final m = m0.replaceAll(RegExp(r'[,:;\-_]'), '.');
        final tm = _timeRe.firstMatch(m);
        if (tm != null &&
            int.parse(tm.group(1)!) <= 23 &&
            int.parse(tm.group(2)!) <= 59) {
          time++;
          seps.add(m0.contains(':') ? ':' : '.');
        }
        final dm = RegExp(r'^-?(\d+)[.,](\d+)$').firstMatch(m);
        if (dm != null) {
          dec++;
          if (m0.contains(',')) commas++;
          intD.add(dm.group(1)!.length);
          fracD.add(dm.group(2)!.length);
        } else if (RegExp(r'^\d+$').hasMatch(m)) {
          integer++;
          intD.add(m.length);
        }
      }
      final n = samples.length;
      final timeNeed = _timeHeader.hasMatch(header) ? 0.4 : 0.6;
      ColumnKind kind;
      final commaDecimal = dec > 0 && commas * 2 > dec;
      if (dates >= 0.5 * n && dates >= 2) {
        kind = ColumnKind.date;
      } else if (!commaDecimal &&
          numCount >= 0.5 * n && time >= timeNeed * numCount && time >= 2) {
        kind = ColumnKind.time;
      } else if (numCount >= 0.5 * n && dec + integer >= 0.6 * numCount && dec >= 0.3 * numCount) {
        kind = ColumnKind.decimal;
      } else if (numCount >= 0.5 * n && integer >= 0.6 * numCount) {
        kind = ColumnKind.integer;
      } else {
        kind = ColumnKind.text;
      }
      out.add(ColumnProfile(
        kind,
        intDigits: _mode(intD),
        fracDigits: kind == ColumnKind.decimal ? _mode(fracD) : 0,
        sep: kind == ColumnKind.date
            ? (dateSeps.isEmpty ? '/' : _modeStr(dateSeps))
            : (seps.isEmpty ? '.' : (seps.where((s) => s == ':').length * 2 > seps.length ? ':' : '.')),
        decSep: commaDecimal ? ',' : '.',
        header: header,
      ));
    }
    return out;
  }

  static ColumnProfile _profileFor(List<ColumnProfile> p, TableCell c) =>
      c.colSpan == 1 && c.col < p.length ? p[c.col] : ColumnProfile(ColumnKind.text);

  // ------------------------------------------------------------ choose

  static void _choose(VerifyTable vt, List<ColumnProfile> profiles) {
    final t = vt.table;
    for (final cell in t.cells) {
      final cands = [
        for (final c in vt.candidates[cell] ?? const <OcrCandidate>[])
          if (clean(c.text).isNotEmpty) c
      ];
      final header = cell.row < t.headerRows;
      final box = cands.where((c) => c.source == 'box').toList();
      if (box.isNotEmpty) {
        final b = box.first;
        cell.text = b.text;
        cell.alternatives = [b.text == '☑' ? '☐' : '☑'];
        cell.confidence = b.confidence;
        cell.numeric = false;
        cell.status = b.confidence >= 0.9 ? CellStatus.ok : CellStatus.check;
        cell.note = b.confidence >= 0.9 ? '' : 'Kotak centang ditebak — pastikan tercentang/tidak';
        continue;
      }
      if (cands.isEmpty) {
        cell.text = '';
        cell.alternatives = const [];
        if (cell.hasInk && !header) {
          cell.status = CellStatus.check;
          cell.note = 'Ada tulisan/coretan yang tidak terbaca';
          cell.confidence = 0;
        } else {
          cell.status = CellStatus.ok;
        }
        continue;
      }
      if (header) {
        // teks cetak: ambil bacaan paling yakin (OCR halaman bila seri)
        var pick = cands.first;
        for (final c in cands) {
          final bonus = c.source == 'page' ? 0.05 : 0.0;
          final pb = pick.source == 'page' ? 0.05 : 0.0;
          if (c.confidence + bonus > pick.confidence + pb) pick = c;
        }
        cell.text = clean(pick.text);
        cell.status = CellStatus.ok;
        cell.confidence = pick.confidence;
        continue;
      }
      final prof = _profileFor(profiles, cell);
      final fixes = [for (final c in cands) _fixValue(c.text, prof)];
      // kata/label di kolom angka (mis. "Batch 2") dibiarkan apa adanya
      final labelLike = prof.kind != ColumnKind.text &&
          fixes.every((f) => !f.valid) &&
          cands.any((c) => !numericish(clean(c.text)));
      var bestI = 0;
      var bestScore = double.negativeInfinity;
      for (var i = 0; i < cands.length; i++) {
        final f = fixes[i];
        var agree = 0;
        for (var j = 0; j < cands.length; j++) {
          if (j != i && _same(fixes[j].value, f.value)) agree++;
        }
        final bias = switch (cands[i].source) {
          'crop' => 0.06,
          'norm' => 0.03,
          _ => 0.0,
        };
        final score = cands[i].confidence +
            (f.valid ? 0.6 : 0) +
            0.35 * agree -
            (f.changed ? 0.08 : 0) +
            bias;
        if (score > bestScore) {
          bestScore = score;
          bestI = i;
        }
      }
      final best = fixes[bestI];
      final raw = clean(cands[bestI].text);
      var agree = 0;
      for (var j = 0; j < cands.length; j++) {
        if (j != bestI && _same(fixes[j].value, best.value)) agree++;
      }
      final distinct = <String>{};
      for (final f in fixes) {
        if (f.value.isNotEmpty) distinct.add(f.value);
      }
      for (final c in cands) {
        distinct.add(clean(c.text));
      }
      cell.text = labelLike ? raw : best.value;
      cell.alternatives = [for (final d in distinct) if (d != cell.text) d];
      cell.confidence = cands[bestI].confidence;
      cell.numeric = prof.numeric && best.valid && !labelLike;

      if (labelLike) {
        cell.status = agree > 0 ? CellStatus.ok : CellStatus.check;
        cell.note = agree > 0 ? '' : 'Teks di kolom angka';
      } else if (!best.valid) {
        cell.status = CellStatus.error;
        cell.note = 'Tidak sesuai pola kolom (${_example(prof)})';
      } else if (best.changed && !_same(best.value, raw)) {
        cell.status = CellStatus.check;
        cell.note = 'Dikoreksi otomatis dari "$raw"';
      } else if (agree == 0 && distinct.length > 1) {
        cell.status = CellStatus.check;
        cell.note = 'Hasil baca berbeda: ${distinct.take(3).join(' / ')}';
      } else if (cands[bestI].confidence < 0.55 && agree == 0) {
        cell.status = CellStatus.check;
        cell.note = 'Keyakinan OCR rendah';
      } else {
        cell.status = CellStatus.ok;
        cell.note = '';
      }
    }
  }

  static bool _same(String a, String b) =>
      a.replaceAll(' ', '').toLowerCase() == b.replaceAll(' ', '').toLowerCase();

  static String _example(ColumnProfile p) => switch (p.kind) {
        ColumnKind.time => 'jam, mis. 09${p.sep}30',
        ColumnKind.decimal => p.fracDigits > 0
            ? 'angka desimal, mis. ${'9' * math.max(1, p.intDigits)}.${'9' * p.fracDigits}'
            : 'angka desimal',
        ColumnKind.integer => 'bilangan bulat',
        ColumnKind.date => 'tanggal, mis. 04${p.sep}03${p.sep}2025',
        _ => 'teks',
      };

  // ------------------------------------------------------------ range

  static double? _num(String s) => double.tryParse(s.replaceAll(',', '.'));

  static void _rangeCheck(VerifyTable vt, List<ColumnProfile> profiles) {
    final t = vt.table;
    for (var col = 0; col < profiles.length; col++) {
      final p = profiles[col];
      if (!p.numeric) continue;
      final cells = [
        for (final c in t.cells)
          if (c.col == col && c.colSpan == 1 && c.row >= t.headerRows && c.numeric) c
      ];
      final vals = [for (final c in cells) _num(c.text)].whereType<double>().toList();
      if (vals.length < 5) continue;
      vals.sort();
      final med = vals[vals.length ~/ 2];
      final dev = [for (final v in vals) (v - med).abs()]..sort();
      final mad = dev[dev.length ~/ 2];
      p
        ..median = med
        ..spread = mad
        ..valid = vals.length;
      final limit = math.max(4 * 1.4826 * mad, math.max(0.15 * med.abs(), 1.0));
      for (final c in cells) {
        final v = _num(c.text);
        if (v == null || (v - med).abs() <= limit) continue;
        String? alt;
        for (final a in c.alternatives) {
          final f = _fixValue(a, p);
          final av = f.valid ? _num(f.value) : null;
          if (av != null && (av - med).abs() <= limit) {
            alt = f.value;
            break;
          }
        }
        if (alt != null) {
          c.alternatives = [c.text, ...c.alternatives.where((x) => x != alt)];
          c
            ..text = alt
            ..status = CellStatus.check
            ..note = 'Dipilih bacaan lain yang sesuai rentang kolom';
        } else {
          c
            ..status = CellStatus.error
            ..note = 'Nilai jauh dari umumnya di kolom ini (±${_fmt(med)})';
        }
      }
    }
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  // ------------------------------------------------------------ relations

  /// Mendeteksi kolom yang merupakan rata-rata/jumlah dari kolom di kirinya
  /// (mis. "Rata Rata Suhu"), lalu memeriksa setiap baris.
  static void _relations(VerifyTable vt, List<ColumnProfile> profiles) {
    final t = vt.table;
    final body = <int, Map<int, TableCell>>{};
    for (final c in t.cells) {
      if (c.row < t.headerRows || c.colSpan != 1 || c.rowSpan != 1) continue;
      (body[c.row] ??= {})[c.col] = c;
    }
    for (var j = 2; j < profiles.length; j++) {
      if (!profiles[j].numeric) continue;
      _Relation? best;
      for (var k = 2; k <= 5 && j - k >= 0; k++) {
        var allNum = true;
        for (var q = j - k; q < j; q++) {
          if (!profiles[q].numeric) allNum = false;
        }
        if (!allNum) break;
        for (final isAvg in [true, false]) {
          var n = 0, ok = 0;
          for (final row in body.values) {
            final vals = _rowVals(row, j - k, j);
            if (vals == null) continue;
            n++;
            if (_holds(vals, isAvg, profiles[j].fracDigits)) ok++;
          }
          if (n >= 3 && ok >= 0.6 * n && (best == null || ok / n > best.ratio)) {
            best = _Relation(k, isAvg, ok / n);
          }
        }
      }
      final rel = best;
      if (rel == null) continue;
      final frac = profiles[j].fracDigits;
      for (final row in body.values) {
        final vals = _rowVals(row, j - rel.k, j);
        if (vals == null || _holds(vals, rel.avg, frac)) continue;
        final involved = [for (var q = j - rel.k; q <= j; q++) row[q]!];
        // cari satu substitusi alternatif yang membuat rumus cocok
        final fixes = <(TableCell, String)>[];
        for (var ii = 0; ii < involved.length; ii++) {
          final cell = involved[ii];
          for (final a in cell.alternatives) {
            final f = _fixValue(a, profiles[cell.col]);
            final av = f.valid ? _num(f.value) : null;
            if (av == null) continue;
            final trial = [...vals]..[ii] = av;
            if (_holds(trial, rel.avg, frac)) fixes.add((cell, f.value));
          }
        }
        if (fixes.length == 1) {
          final (cell, value) = fixes.first;
          cell.alternatives = [cell.text, ...cell.alternatives.where((x) => x != value)];
          cell
            ..text = value
            ..status = CellStatus.check
            ..note = 'Dikoreksi agar ${rel.avg ? 'rata-rata' : 'jumlah'} baris cocok';
          continue;
        }
        final parts = vals.sublist(0, vals.length - 1);
        final expect = rel.avg
            ? parts.reduce((a, b) => a + b) / parts.length
            : parts.reduce((a, b) => a + b);
        final target = involved.last;
        if (target.status != CellStatus.error) {
          target
            ..status = CellStatus.error
            ..note = '${rel.avg ? 'Rata-rata' : 'Jumlah'} tidak cocok: '
                'hitungan = ${expect.toStringAsFixed(math.max(frac, 1))}';
        }
        for (final c in involved.take(involved.length - 1)) {
          if (c.status == CellStatus.ok) {
            c
              ..status = CellStatus.check
              ..note = 'Periksa: ${rel.avg ? 'rata-rata' : 'jumlah'} baris tidak cocok';
          }
        }
      }
    }
  }

  static List<double>? _rowVals(Map<int, TableCell> row, int from, int to) {
    final out = <double>[];
    for (var q = from; q <= to; q++) {
      final c = row[q];
      if (c == null || !c.numeric) return null;
      final v = _num(c.text);
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  static bool _holds(List<double> vals, bool avg, int frac) {
    final parts = vals.sublist(0, vals.length - 1);
    final s = parts.reduce((a, b) => a + b);
    final expect = avg ? s / parts.length : s;
    final tol = 0.5 * math.pow(10, -math.max(frac, 1)) + 0.011;
    return (vals.last - expect).abs() <= tol;
  }

  // ------------------------------------------------------------ vocabulary

  static void _vocabulary(List<VerifyTable> tables,
      Map<VerifyTable, List<ColumnProfile>> profiles, List<String> dict) {
    final counts = <String, int>{};
    final forms = <String, String>{};
    final textCells = <TableCell>[];
    for (final vt in tables) {
      final p = profiles[vt]!;
      for (final c in vt.table.cells) {
        if (c.row < vt.table.headerRows) continue;
        final prof = _profileFor(p, c);
        if (prof.kind != ColumnKind.text) continue;
        final v = c.text.trim();
        if (v.length < 3 || numericish(v)) continue;
        textCells.add(c);
        final k = v.toLowerCase();
        counts[k] = (counts[k] ?? 0) + 1;
        forms.putIfAbsent(k, () => v);
      }
    }
    final dictLower = {for (final d in dict) d.toLowerCase(): d};
    for (final c in textCells) {
      final v = c.text.trim();
      final k = v.toLowerCase();
      if (dictLower.containsKey(k)) continue;
      final maxD = v.length <= 5 ? 1 : 2;
      String? target;
      var targetCount = 0;
      if ((counts[k] ?? 0) <= 1) {
        counts.forEach((w, n) {
          if (n >= 2 && w != k && n > targetCount && levenshtein(w, k) <= maxD) {
            target = forms[w];
            targetCount = n;
          }
        });
      }
      if (target == null && v.length >= 4) {
        for (final e in dictLower.entries) {
          if (levenshtein(e.key, k) <= 1) {
            target = e.value;
            break;
          }
        }
      }
      final tgt = target;
      if (tgt != null && tgt != v) {
        c.alternatives = [v, ...c.alternatives.where((x) => x != tgt)];
        c.text = tgt;
        if (c.status == CellStatus.ok) {
          c
            ..status = CellStatus.check
            ..note = 'Ejaan disesuaikan dengan "$tgt"';
        }
      }
    }
  }

  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      }
      prev = cur;
    }
    return prev[b.length];
  }
}

class _Relation {
  const _Relation(this.k, this.avg, this.ratio);
  final int k;
  final bool avg;
  final double ratio;
}
