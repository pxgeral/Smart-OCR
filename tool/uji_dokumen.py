#!/usr/bin/env python3
"""Bandingkan teks hasil konversi dengan teks asli dokumen (pdftotext).

Struktur masukan:
  <root>/truth/<dokumen>.txt            teks asli (pdftotext)
  <root>/out/<dokumen>/<mode>/hasil.*   keluaran test/e2e_sample_test.dart

Keluaran: tabel Markdown ke stdout (untuk GITHUB_STEP_SUMMARY). Kode keluar 1
bila tidak ada satu pun hasil yang dapat dinilai atau berkas DOCX/XLSX rusak.
Pengukuran tidak peduli urutan kolom/baris (F1 kata), ditambah kemiripan
urutan (SequenceMatcher) supaya tata letak yang kacau tetap terlihat.
"""
import difflib
import re
import sys
import zipfile
from collections import Counter
from pathlib import Path


def words(text: str) -> list[str]:
    return re.findall(r"[^\W_]+", text.casefold())


def score(truth: list[str], out: list[str]):
    if not truth or not out:
        return 0.0, 0.0, 0.0, 0.0
    common = sum((Counter(truth) & Counter(out)).values())
    recall = common / len(truth)
    precision = common / len(out)
    f1 = 0.0 if common == 0 else 2 * recall * precision / (recall + precision)
    seq = difflib.SequenceMatcher(None, truth, out, autojunk=False).ratio()
    return recall, precision, f1, seq


def missing(truth: list[str], out: list[str], limit: int = 30) -> list[str]:
    """Kata asli yang tidak muncul di hasil (menurut jumlah), urut kemunculan."""
    left = Counter(truth) - Counter(out)
    seen, res = Counter(), []
    for w in truth:
        if seen[w] < left[w]:
            seen[w] += 1
            res.append(w)
    return res[:limit]


def check_docx(path: Path) -> str:
    try:
        import docx  # python-docx

        d = docx.Document(str(path))
        return f"{len(d.paragraphs)} paragraf, {len(d.tables)} tabel"
    except Exception as e:  # noqa: BLE001
        return f"RUSAK ({type(e).__name__}: {e})"


def check_xlsx(path: Path) -> str:
    try:
        import openpyxl

        wb = openpyxl.load_workbook(str(path))
        return ", ".join(f"{ws.title}:{ws.max_row}x{ws.max_column}" for ws in wb.worksheets)
    except Exception as e:  # noqa: BLE001
        return f"RUSAK ({type(e).__name__}: {e})"


def main() -> int:
    root = Path(sys.argv[1])
    rows, bad, scored, notes = [], 0, 0, []
    for truth_file in sorted((root / "truth").glob("*.txt")):
        doc = truth_file.stem
        truth = words(truth_file.read_text(encoding="utf-8", errors="ignore"))
        for mode in ("ubah", "asli"):
            d = root / "out" / doc / mode
            txt = d / "hasil.txt"
            if not txt.exists():
                rows.append(f"| {doc} | {mode} | - | - | - | - | - | tidak ada keluaran |")
                bad += 1
                continue
            out = words(txt.read_text(encoding="utf-8", errors="ignore"))
            r, p, f1, seq = score(truth, out)
            scored += 1
            dx = check_docx(d / "hasil.docx") if (d / "hasil.docx").exists() else "tidak ada"
            xl = check_xlsx(d / "hasil.xlsx") if (d / "hasil.xlsx").exists() else "tidak ada"
            if "RUSAK" in dx or "RUSAK" in xl or dx == "tidak ada":
                bad += 1
            rows.append(
                f"| {doc} | {mode} | {len(truth)} | {len(out)} | {r:.0%} | {p:.0%} | {seq:.0%} | "
                f"DOCX: {dx}; XLSX: {xl} |"
            )
            if mode == "ubah" and r < 0.995:
                miss = missing(truth, out)
                notes.append(f"- **{doc}** kata asli yang hilang/salah baca: {', '.join(miss) or '-'}")
                if len(out) <= 150:
                    notes.append(f"  - teks hasil: `{' '.join(out)}`")
    print("| Dokumen | Mode | Kata asli | Kata hasil | Recall | Presisi | Kemiripan urutan | Berkas |")
    print("|---|---|---:|---:|---:|---:|---:|---|")
    print("\n".join(rows))
    if notes:
        print("\n" + "\n".join(notes))
    print(
        "\nRecall = porsi kata asli yang muncul di hasil; Presisi = porsi kata hasil yang benar. "
        "Pembaca OCR di uji ini Tesseract (ML Kit hanya berjalan di Android), "
        "jadi angka menilai alur analisis tata letak + perakitan + ekspor, bukan akurasi ML Kit."
    )
    return 1 if scored == 0 or bad else 0


if __name__ == "__main__":
    sys.exit(main())
