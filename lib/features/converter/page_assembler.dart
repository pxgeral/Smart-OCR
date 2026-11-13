import 'dart:math' as math;

import '../../core/raster.dart';
import '../../models/converted_content.dart';
import '../../models/enums.dart';
import '../../models/ocr_result.dart';
import '../../models/table_data.dart';
import 'cell_verifier.dart';
import 'document_builder.dart';
import 'layout_analyzer.dart';
import 'page_analyzer.dart';
import 'table_detector.dart';

/// Data satu halaman untuk tahap perakitan (semua bisa dikirim ke Isolate).
class AssemblyPage {
  AssemblyPage(this.analysis, this.ocr, this.mosaicA, this.mosaicB);
  final PageAnalysis analysis;
  final OcrPage ocr; // koordinat gambar ternormalisasi
  final List<OcrPage> mosaicA, mosaicB;

}

/// Tahap 3: gabungkan struktur tabel, hasil OCR halaman & OCR per sel,
/// teks di luar tabel, lalu verifikasi tulisan tangan.
abstract final class PageAssembler {
  static ConvertedContent assemble(
    List<AssemblyPage> pages, {
    DocumentKind? force,
    List<String> dictionary = const [],
    bool keepOriginal = false,
  }) {
    final withTables = pages
        .where((p) => p.analysis.tables
            .any((t) => t.colWidths.length >= 2 && t.rowHeights.length >= 2))
        .length;
    var kind = force ??
        (withTables > 0 && withTables * 2 >= pages.length
            ? DocumentKind.table
            : DocumentKind.document);

    final verify = <VerifyTable>[];
    final out = <PageContent>[];
    var foundAny = withTables > 0;
    for (final p in pages) {
      final content = _page(p, kind, force, verify);
      if (!foundAny && content.tables.isNotEmpty) foundAny = true;
      out.add(content);
    }
    if (force == null && kind == DocumentKind.table && !foundAny) {
      kind = DocumentKind.document;
    }
    CellVerifier.verify(verify,
        dictionary: dictionary, keepOriginal: keepOriginal);
    return ConvertedContent(kind: kind, pages: out);
  }

  static PageContent _page(AssemblyPage p, DocumentKind kind,
      DocumentKind? force, List<VerifyTable> verify) {
    final a = p.analysis;
    final landscape = a.width > a.height;
    final pxToPt = (landscape ? 842.0 : 595.0) / a.width;
    var boxes = _dropWatermark(p.ocr.boxes);
    // kolom yang garisnya tidak terlihat di foto dipulihkan dari celah teks
    final tables = [for (final t in a.tables) _splitColumnsByText(t, boxes)];
    for (final info in tables) {
      boxes = _splitAcrossCells(boxes, info);
    }

    final elements = <PageElement>[];
    final used = List<bool>.filled(boxes.length, false);

    for (var ti = 0; ti < tables.length; ti++) {
      final info = tables[ti];
      final cands = <TableCell, List<OcrCandidate>>{};
      final cells = <TableCell>[];
      for (var cellIndex = 0; cellIndex < info.cells.length; cellIndex++) {
        final ci = info.cells[cellIndex];
        final cell = TableCell(
          row: ci.row,
          col: ci.col,
          rowSpan: ci.rowSpan,
          colSpan: ci.colSpan,
          box: ci.box,
          fill: isFillColor(ci.fill) ? ci.fill : null,
          fontColor: ci.ink,
          align: ci.align,
          hasInk: ci.hasInk,
        );
        cells.add(cell);
        final list = <OcrCandidate>[];
        if (ci.checkbox != 0) {
          // kotak centang: tidak perlu OCR
          final checked = ci.checkbox.abs() == 2;
          list.add(OcrCandidate(checked ? '☑' : '☐', ci.checkbox > 0 ? 1.0 : 0.5, 'box'));
          cell.align = CellAlign.center;
          for (var i = 0; i < boxes.length; i++) {
            final b = boxes[i];
            final cx = (b.left + b.right) / 2, cy = b.centerY;
            if (cx >= ci.box[0] && cx < ci.box[2] && cy >= ci.box[1] && cy < ci.box[3]) used[i] = true;
          }
          cands[cell] = list;
          continue;
        }
        // OCR halaman penuh: kata yang titik tengahnya di dalam sel
        final inside = <OcrBox>[];
        for (var i = 0; i < boxes.length; i++) {
          final b = boxes[i];
          final cx = (b.left + b.right) / 2, cy = b.centerY;
          if (cx >= ci.box[0] && cx < ci.box[2] && cy >= ci.box[1] && cy < ci.box[3]) {
            inside.add(b);
            used[i] = true;
          }
        }
        if (inside.isNotEmpty) list.add(_join(inside, 'page'));
        // OCR per sel dari mosaik
        if (ci.slot >= 0 && ci.slot < a.slots.length) {
          final s = a.slots[ci.slot];
          for (final (src, ocrs) in [('crop', p.mosaicA), ('norm', p.mosaicB)]) {
            if (s.mosaic >= ocrs.length) continue;
            final hits = [
              for (final b in ocrs[s.mosaic].boxes)
                if ((b.left + b.right) / 2 >= s.x &&
                    (b.left + b.right) / 2 < s.x + s.w &&
                    b.centerY >= s.y &&
                    b.centerY < s.y + s.h)
                  b
            ];
            if (hits.isNotEmpty) list.add(_join(hits, src));
          }
        }
        cands[cell] = list;
      }
      final table = TableData(
        colWidths: info.colWidths,
        rowHeights: info.rowHeights,
        cells: cells,
        left: info.left,
        top: info.top,
      );
      table.headerRows = _headerRows(table, cands);
      for (final c in cells) {
        if (c.row < table.headerRows) c.bold = true;
      }
      _fontSizes(table, info, pxToPt);
      verify.add(VerifyTable(table, cands));
      elements.add(TableElement(table));
    }

    // teks di luar tabel
    final free = [
      for (var i = 0; i < boxes.length; i++)
        if (!used[i] && !_insideTable(boxes[i], tables)) boxes[i]
    ];
    // coretan tanda tangan/paraf terbaca sebagai 1-2 huruf berukuran besar
    if (free.length >= 4) {
      final hs = free.map((b) => b.height).toList()..sort();
      final med = hs[hs.length ~/ 2];
      free.removeWhere((b) => b.height > med * 2.2 && b.text.trim().length <= 3);
    }
    final freePage = OcrPage(
        index: p.ocr.index, width: p.ocr.width, height: p.ocr.height, boxes: free);
    if (tables.isEmpty && kind == DocumentKind.table) {
      final layout = LayoutAnalyzer.analyze(freePage);
      final t = TableDetector.detect(layout, force: force == DocumentKind.table);
      if (t != null) {
        elements.add(TableElement(t));
        return PageContent(
            width: a.width.toDouble(),
            height: a.height.toDouble(),
            elements: elements,
            imagePath: a.imagePath);
      }
    }
    // Baris dengan beberapa kelompok teks berjauhan (formulir dua kolom,
    // blok tanda tangan) disimpan per segmen beserta posisinya; baris
    // tunggal digabung menjadi paragraf.
    final layout = LayoutAnalyzer.analyze(freePage, cellGap: 2.2);
    final single = <LayoutRow>[];
    var lineId = 0;
    for (final row in layout.rows) {
      if (row.cells.length < 2) {
        single.add(row);
        continue;
      }
      final style = _bandStyle(row, a.bands);
      final pt = (row.height * pxToPt / 1.25).clamp(6.0, 28.0).toDouble();
      for (final cell in row.cells) {
        elements.add(TextElement(DocBlock(
          cell.text,
          left: cell.left,
          right: cell.right,
          top: row.top,
          bottom: row.bottom,
          fontPt: pt,
          bold: style?.fill != null,
          fill: style?.fill,
          fontColor: style?.color,
          line: lineId,
        )));
      }
      lineId++;
    }
    elements.addAll(DocumentBuilder.build(
      PageLayout(single, layout.lineHeight, layout.width),
      pxToPt: pxToPt,
      styleAt: (row) => _bandStyle(row, a.bands),
    ).map(TextElement.new));

    // ukuran huruf teks biasa diseragamkan (tinggi kotak OCR bervariasi);
    // hanya judul yang jelas lebih besar yang dipertahankan
    final pts = [
      for (final e in elements)
        if (e is TextElement && e.block.fontPt > 0) e.block.fontPt
    ]..sort();
    if (pts.length >= 3) {
      final med = pts[pts.length ~/ 2];
      for (var i = 0; i < elements.length; i++) {
        final e = elements[i];
        if (e is TextElement) {
          final pt = e.block.fontPt;
          final heading = e.block.type == BlockType.heading;
          final hi = heading ? 1.45 : 2.2;
          if (pt > 0 && pt >= med * 0.6 && pt <= med * hi && pt != med) {
            elements[i] = TextElement(e.block.withFont(med));
          }
        }
      }
    }
    elements.sort((x, y) {
      final d = x.top.compareTo(y.top);
      return d != 0 ? d : x.left.compareTo(y.left);
    });
    return PageContent(
      width: a.width.toDouble(),
      height: a.height.toDouble(),
      elements: elements,
      imagePath: a.imagePath,
    );
  }

  /// Garis kolom yang tidak terdeteksi (pudar/tertutup warna di foto)
  /// ditemukan dari celah kosong yang konsisten di antara kata-kata pada
  /// banyak baris kolom yang sama; kolom lalu dipecah di posisi itu.
  static TableInfo _splitColumnsByText(TableInfo t, List<OcrBox> boxes) {
    var info = t;
    for (var c = info.colWidths.length - 1; c >= 0; c--) {
      final x = _hiddenBoundary(info, c, boxes);
      if (x != null) info = _splitColumn(info, c, x, boxes);
    }
    return info;
  }

  static double? _hiddenBoundary(TableInfo t, int c, List<OcrBox> boxes) {
    var x0 = t.left;
    for (var k = 0; k < c; k++) {
      x0 += t.colWidths[k];
    }
    final cw = t.colWidths[c];
    final x1 = x0 + cw;
    if (cw <= 0) return null;
    final gaps = <double>[];
    var rowsWithWords = 0;
    for (final cell in t.cells) {
      if (cell.col != c || cell.colSpan != 1) continue;
      final words = [
        for (final b in boxes)
          if ((b.left + b.right) / 2 >= cell.box[0] &&
              (b.left + b.right) / 2 < cell.box[2] &&
              b.centerY >= cell.box[1] &&
              b.centerY < cell.box[3])
            b
      ]..sort((a, b) => a.left.compareTo(b.left));
      if (words.isEmpty) continue;
      rowsWithWords++;
      if (words.length < 2) continue;
      final hs = words.map((w) => w.height).toList()..sort();
      final h = hs[hs.length ~/ 2];
      var best = 0.0, at = 0.0;
      for (var i = 1; i < words.length; i++) {
        final g = words[i].left - words[i - 1].right;
        if (g > best) {
          best = g;
          at = (words[i].left + words[i - 1].right) / 2;
        }
      }
      if (best > math.max(1.0 * h, cw * 0.06)) gaps.add(at);
    }
    if (gaps.length < 3 || rowsWithWords < 4) return null;
    gaps.sort();
    // kelompok celah terbesar
    final tol = cw * 0.07;
    var bestStart = 0, bestLen = 0;
    for (var i = 0; i < gaps.length; i++) {
      var j = i;
      while (j + 1 < gaps.length && gaps[j + 1] - gaps[i] <= 2 * tol) {
        j++;
      }
      if (j - i + 1 > bestLen) {
        bestLen = j - i + 1;
        bestStart = i;
      }
    }
    if (bestLen < math.max(3, rowsWithWords * 0.45)) return null;
    final grp = gaps.sublist(bestStart, bestStart + bestLen);
    final x = grp[grp.length ~/ 2];
    if (x - x0 < cw * 0.12 || x1 - x < cw * 0.12) return null;
    return x;
  }

  static TableInfo _splitColumn(TableInfo t, int c, double x, List<OcrBox> boxes) {
    var x0 = t.left;
    for (var k = 0; k < c; k++) {
      x0 += t.colWidths[k];
    }
    final widths = [
      ...t.colWidths.sublist(0, c),
      x - x0,
      t.colWidths[c] - (x - x0),
      ...t.colWidths.sublist(c + 1),
    ];
    bool wordsIn(double l, double r, List<double> box) => boxes.any((b) =>
        (b.left + b.right) / 2 >= l &&
        (b.left + b.right) / 2 < r &&
        b.centerY >= box[1] &&
        b.centerY < box[3]);
    bool straddles(List<double> box) => boxes.any((b) =>
        b.centerY >= box[1] &&
        b.centerY < box[3] &&
        b.left < x - 2 &&
        b.right > x + 2 &&
        (b.left + b.right) / 2 >= box[0] &&
        (b.left + b.right) / 2 < box[2]);
    final cells = <CellInfo>[];
    CellInfo copy(CellInfo ci, {int? col, int? colSpan, List<double>? box, bool? ink, int? slot}) {
      final n = CellInfo(
        row: ci.row,
        col: col ?? ci.col,
        rowSpan: ci.rowSpan,
        colSpan: colSpan ?? ci.colSpan,
        box: box ?? ci.box,
        fill: ci.fill,
        hasInk: ink ?? ci.hasInk,
        ink: ci.ink,
        align: ci.align,
        inkHeight: ci.inkHeight,
        checkbox: ci.checkbox,
      );
      n.slot = slot ?? ci.slot;
      return n;
    }

    for (final ci in t.cells) {
      if (ci.col > c) {
        cells.add(copy(ci, col: ci.col + 1));
      } else if (ci.col + ci.colSpan - 1 < c) {
        cells.add(ci);
      } else if (ci.colSpan == 1 && !straddles(ci.box) && ci.checkbox == 0) {
        final lb = [ci.box[0], ci.box[1], x, ci.box[3]];
        final rb = [x, ci.box[1], ci.box[2], ci.box[3]];
        final lw = wordsIn(ci.box[0], x, ci.box), rw = wordsIn(x, ci.box[2], ci.box);
        final anyWords = lw || rw;
        cells.add(copy(ci, box: lb, ink: lw || (!anyWords && ci.hasInk), slot: -1));
        cells.add(copy(ci, col: c + 1, box: rb, ink: rw, slot: -1));
      } else {
        cells.add(copy(ci, colSpan: ci.colSpan + 1));
      }
    }
    return TableInfo(
      colWidths: widths,
      rowHeights: t.rowHeights,
      left: t.left,
      top: t.top,
      cells: cells,
    );
  }

  /// Kata hasil OCR halaman yang melintasi garis kolom (mis. "88" padahal
  /// "8" | "8") dipecah per sel memakai posisi karakter, atau proporsional
  /// bila posisi karakter tidak tersedia.
  static List<OcrBox> _splitAcrossCells(List<OcrBox> boxes, TableInfo t) {
    final out = <OcrBox>[];
    for (var i = 0; i < boxes.length; i++) {
      final b = boxes[i];
      if (b.text.length < 2) {
        out.add(b);
        continue;
      }
      final cy = b.centerY;
      final hits = <CellInfo>[];
      for (final c in t.cells) {
        if (cy < c.box[1] || cy >= c.box[3]) continue;
        final ov = math.min(b.right, c.box[2]) - math.max(b.left, c.box[0]);
        if (ov > b.width * 0.2 && ov > 2) hits.add(c);
      }
      if (hits.length < 2) {
        out.add(b);
        continue;
      }
      hits.sort((x, y) => x.box[0].compareTo(y.box[0]));
      final parts = <OcrBox>[];
      for (final c in hits) {
        final sb = StringBuffer();
        double? l, r;
        for (var k = 0; k < b.text.length; k++) {
          final double cl, cr;
          if (b.chars.length == b.text.length) {
            cl = b.chars[k][0];
            cr = b.chars[k][1];
          } else {
            final cw = b.width / b.text.length;
            cl = b.left + k * cw;
            cr = cl + cw;
          }
          final mid = (cl + cr) / 2;
          if (mid >= c.box[0] && mid < c.box[2]) {
            sb.write(b.text[k]);
            l = math.min(l ?? cl, cl);
            r = math.max(r ?? cr, cr);
          }
        }
        final txt = sb.toString().trim();
        if (txt.isEmpty || l == null || r == null) continue;
        // potongan 1 huruf (mis. "P" dari "Pek" yang menempel garis) bukan
        // isi sel tetangga; hanya angka tunggal yang boleh dipecah
        if (txt.length < 2 && !RegExp(r'^\d$').hasMatch(txt)) {
          parts.clear();
          break;
        }
        parts.add(OcrBox(
            text: txt, left: l, top: b.top, right: r, bottom: b.bottom,
            confidence: b.confidence * 0.95));
      }
      if (parts.length >= 2) {
        out.addAll(parts); // kotak asli diganti potongannya
      } else {
        out.add(b);
      }
    }
    return out;
  }

  static ({int? fill, int? color})? _bandStyle(LayoutRow row, List<BandInfo> bands) {
    final cx = (row.left + row.right) / 2, cy = (row.top + row.bottom) / 2;
    for (final b in bands) {
      if (cx >= b.left && cx <= b.right && cy >= b.top - 4 && cy <= b.bottom + 4) {
        return (fill: b.fill, color: colorLum(b.fill) < 150 ? 0xFFFFFF : null);
      }
    }
    return null;
  }

  static bool _insideTable(OcrBox b, List<TableInfo> tables) {
    final cx = (b.left + b.right) / 2, cy = b.centerY;
    return tables.any((t) => cx >= t.left && cx <= t.right && cy >= t.top && cy <= t.bottom);
  }

  /// Buang tanda air aplikasi pemindai ("Dipindai dengan CamScanner").
  static List<OcrBox> _dropWatermark(List<OcrBox> boxes) {
    final marks = boxes
        .where((b) => b.text.toLowerCase().contains('camscanner'))
        .toList();
    if (marks.isEmpty) return boxes;
    return [
      for (final b in boxes)
        if (!marks.any((m) =>
            (b.centerY - m.centerY).abs() < m.height * 3.5 &&
            b.right > m.left - m.width * 1.2 &&
            b.left < m.right + m.width * 0.5))
          b
    ];
  }

  static OcrCandidate _join(List<OcrBox> boxes, String source) {
    final sorted = [...boxes]..sort((a, b) => a.centerY.compareTo(b.centerY));
    final hs = sorted.map((b) => b.height).toList()..sort();
    final med = hs[hs.length ~/ 2];
    final lines = <List<OcrBox>>[];
    for (final b in sorted) {
      if (lines.isNotEmpty) {
        final l = lines.last;
        final cy = l.fold<double>(0, (s, x) => s + x.centerY) / l.length;
        if ((b.centerY - cy).abs() <= med * 0.6) {
          l.add(b);
          continue;
        }
      }
      lines.add([b]);
    }
    final text = [
      for (final l in lines)
        (l..sort((a, b) => a.left.compareTo(b.left))).map((b) => b.text).join(' ')
    ].join('\n');
    final conf = boxes.fold<double>(0, (s, b) => s + b.confidence) / boxes.length;
    return OcrCandidate(text, conf, source);
  }

  /// Baris kepala: baris atas yang mayoritas berwarna atau berisi sel gabungan
  /// melebar; bila tidak ada, baris pertama berupa label tanpa angka.
  static int _headerRows(TableData t, Map<TableCell, List<OcrCandidate>> cands) {
    final rows = t.rowCount;
    if (rows < 2) return 0;
    double filledFrac(int r) {
      var n = 0, f = 0;
      for (final c in t.cells) {
        if (r >= c.row && r < c.row + c.rowSpan) {
          n += c.colSpan;
          if (c.fill != null) f += c.colSpan;
        }
      }
      return n == 0 ? 0 : f / n;
    }

    bool wideMerge(int r) => t.cells.any((c) =>
        c.row == r && c.colSpan >= 2 && c.colSpan < t.columnCount && !_numericRow(c, cands));

    var hr = 0;
    while (hr < rows - 1 && (filledFrac(hr) >= 0.6 || (hr < 3 && wideMerge(hr) && filledFrac(hr) > 0))) {
      hr++;
    }
    if (hr > 0) {
      // sel kepala yang memanjang ke bawah memperluas area kepala
      var changed = true;
      while (changed) {
        changed = false;
        for (final c in t.cells) {
          if (c.row < hr && c.row + c.rowSpan > hr) {
            hr = c.row + c.rowSpan;
            changed = true;
          }
        }
      }
    } else if (rows >= 3) {
      // tanpa warna: baris-baris atas berisi label teks (tanpa angka)
      String textOf(TableCell c) {
        final k = cands[c] ?? const <OcrCandidate>[];
        final page = k.where((x) => x.source == 'page');
        return (page.isNotEmpty ? page.first : (k.isEmpty ? null : k.first))?.text ?? '';
      }

      bool labelRow(int r) {
        final rowCells = [for (final c in t.cells) if (c.row == r) c];
        final texts = [for (final c in rowCells) textOf(c).trim()]
            .where((s) => s.isNotEmpty)
            .toList();
        // angka pada bacaan mana pun (halaman/potongan) = baris data
        final numeric = [
          for (final c in rowCells)
            for (final k in cands[c] ?? const <OcrCandidate>[]) k.text
        ].where((s) => RegExp(r'\d').hasMatch(s) && !RegExp(r'[A-Za-z]{3,}').hasMatch(s)).length;
        final labels = texts.where((s) => RegExp(r'[A-Za-z]{2,}').hasMatch(s)).length;
        final merged = rowCells.any((c) => c.colSpan >= 2 && c.colSpan < t.columnCount);
        return texts.isNotEmpty &&
            numeric == 0 &&
            labels >= texts.length * 0.6 &&
            (texts.length >= 2 || merged);
      }

      final labelRows = [for (var i = 0; i < rows; i++) labelRow(i)];
      var r = 0;
      // formulir (label di setiap baris) tidak punya baris kepala
      if (labelRows.where((x) => x).length <= rows / 2) {
        while (r < math.min(4, rows - 1) && labelRows[r]) {
          r++;
        }
      }
      hr = r;
      var changed = hr > 0;
      while (changed) {
        changed = false;
        for (final c in t.cells) {
          if (c.row < hr && c.row + c.rowSpan > hr) {
            hr = c.row + c.rowSpan;
            changed = true;
          }
        }
      }
    }
    return math.min(hr, (rows / 2).floor());
  }

  static bool _numericRow(TableCell c, Map<TableCell, List<OcrCandidate>> cands) {
    final k = cands[c];
    if (k == null || k.isEmpty) return false;
    return CellVerifier.numericish(k.first.text);
  }

  static void _fontSizes(TableData t, TableInfo info, double pxToPt) {
    final head = <double>[], body = <double>[];
    for (var i = 0; i < info.cells.length; i++) {
      final ci = info.cells[i];
      if (!ci.hasInk || ci.inkHeight <= 0) continue;
      // tinggi tinta sel kepala bisa 2-3 baris; ambil per baris kasar
      if (ci.row < t.headerRows) {
        head.add(ci.inkHeight);
      } else if (ci.rowSpan == 1) {
        body.add(ci.inkHeight);
      }
    }
    double med(List<double> v) {
      v.sort();
      return v[v.length ~/ 2];
    }

    final rowH = [...t.rowHeights]..sort();
    final medRowPt = rowH.isEmpty ? 14.0 : rowH[rowH.length ~/ 2] * pxToPt;
    final maxBody = math.max(6.0, medRowPt * 0.62);
    t.bodyFontPt = body.isEmpty
        ? math.min(10.0, maxBody)
        : (med(body) * pxToPt / 0.8).clamp(6.0, math.min(12.0, maxBody)).toDouble();
    // teks kepala cetak biasanya lebih kecil dari tulisan tangan
    t.headerFontPt = head.isEmpty
        ? math.max(6.0, t.bodyFontPt - 1)
        : math.min(t.bodyFontPt, math.max(6.0, (med(head) * pxToPt / 1.6).clamp(6.0, 11.0).toDouble()));
  }
}
