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
    CellVerifier.verify(verify, dictionary: dictionary);
    return ConvertedContent(kind: kind, pages: out);
  }

  static PageContent _page(AssemblyPage p, DocumentKind kind,
      DocumentKind? force, List<VerifyTable> verify) {
    final a = p.analysis;
    final landscape = a.width > a.height;
    final pxToPt = (landscape ? 842.0 : 595.0) / a.width;
    final boxes = _dropWatermark(p.ocr.boxes);

    final elements = <PageElement>[];
    final used = List<bool>.filled(boxes.length, false);

    for (final info in a.tables) {
      final cands = <TableCell, List<OcrCandidate>>{};
      final cells = <TableCell>[];
      for (final ci in info.cells) {
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
        if (!used[i] && !_insideTable(boxes[i], a.tables)) boxes[i]
    ];
    final freePage = OcrPage(
        index: p.ocr.index, width: p.ocr.width, height: p.ocr.height, boxes: free);
    if (a.tables.isEmpty && kind == DocumentKind.table) {
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
    final layout = LayoutAnalyzer.analyze(freePage, cellGap: double.infinity);
    elements.addAll(DocumentBuilder.build(
      layout,
      pxToPt: pxToPt,
      styleAt: (row) => _bandStyle(row, a.bands),
    ).map(TextElement.new));

    elements.sort((x, y) => x.top.compareTo(y.top));
    return PageContent(
      width: a.width.toDouble(),
      height: a.height.toDouble(),
      elements: elements,
      imagePath: a.imagePath,
    );
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
      final first = [for (final c in t.cells) if (c.row == 0) c];
      final texts = [
        for (final c in first)
          for (final k in cands[c] ?? const <OcrCandidate>[])
            if (k.source == 'page') k.text
      ];
      final filled = texts.where((s) => s.trim().isNotEmpty).length;
      final digits = texts.where((s) => RegExp(r'\d').hasMatch(s)).length;
      final letters = texts.where((s) => RegExp(r'[A-Za-z]{2,}').hasMatch(s)).length;
      if (filled >= 2 && digits == 0 && letters >= filled * 0.6 && filled >= first.length * 0.5) {
        hr = 1;
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
