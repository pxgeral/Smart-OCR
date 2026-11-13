#!/usr/bin/env python3
"""Implementasi acuan terjemahan offline (Python) untuk membandingkan mesin Dart.

Algoritma sama dengan lib/features/translate/offline/marian_engine.dart:
SentencePiece sumber -> id lewat vocab.json -> encoder ONNX -> dekoder ONNX
rakus (greedy, token awal = <pad>, <pad> dilarang) sampai </s>.

Pemakaian: ref_terjemah.py <folder assets/models> <keluaran.json>
"""
import json
import math
import sys
import time

import numpy as np
import onnxruntime as ort
import sentencepiece as spm

KALIMAT = {
    "id-en": [
        "Saya makan nasi goreng di warung kemarin sore.",
        "Pemerintah akan membangun jembatan baru di Makassar tahun depan.",
        "Laporan ini menjelaskan hasil survei lapangan dan rekomendasi perbaikan.",
        "Harga bahan bangunan naik 5 persen bulan ini.",
        "Silakan tandatangani formulir ini sebelum tanggal 15 Maret 2025.",
        "Kuat tekan beton diuji setelah perawatan selama 28 hari.",
        "Terima kasih atas kerja sama Anda.",
    ],
    "en-id": [
        "The meeting will be held on Monday at 9 a.m.",
        "Please submit the completed form to the office before the deadline.",
        "Concrete strength was tested after 28 days of curing.",
        "The total cost of the project is estimated at 2.5 million dollars.",
        "Thank you for your cooperation.",
        "The site survey found three cracks in the retaining wall.",
    ],
}


def load(root, d):
    base = f"{root}/{d}"
    vocab = json.load(open(f"{base}/vocab.json", encoding="utf-8"))
    inv = {v: k for k, v in vocab.items()}
    so = ort.SessionOptions()
    enc = ort.InferenceSession(f"{base}/encoder.onnx", so, providers=["CPUExecutionProvider"])
    dec = ort.InferenceSession(f"{base}/decoder.onnx", so, providers=["CPUExecutionProvider"])
    sp = spm.SentencePieceProcessor(model_file=f"{base}/source.spm")
    print(f"[{d}] encoder in={[i.name for i in enc.get_inputs()]} out={[o.name for o in enc.get_outputs()]}")
    print(f"[{d}] decoder in={[i.name for i in dec.get_inputs()]} out={[o.name for o in dec.get_outputs()]}")
    need_enc = {"input_ids", "attention_mask"}
    need_dec = {"input_ids", "encoder_hidden_states", "encoder_attention_mask"}
    assert need_enc <= {i.name for i in enc.get_inputs()}, "nama input encoder berbeda"
    assert need_dec <= {i.name for i in dec.get_inputs()}, "nama input dekoder berbeda"
    assert "last_hidden_state" in [o.name for o in enc.get_outputs()]
    assert "logits" in [o.name for o in dec.get_outputs()]
    return vocab, inv, enc, dec, sp


def translate(vocab, inv, enc, dec, sp, text):
    eos, unk, pad = vocab["</s>"], vocab["<unk>"], vocab["<pad>"]
    src = [vocab.get(p, unk) for p in sp.encode(text, out_type=str)] + [eos]
    n = len(src)
    ids = np.array([src], dtype=np.int64)
    mask = np.ones((1, n), dtype=np.int64)
    hidden = enc.run(["last_hidden_state"], {"input_ids": ids, "attention_mask": mask})[0]
    out = [pad]
    for _ in range(min(300, math.ceil(n * 1.5) + 10)):
        logits = dec.run(
            ["logits"],
            {
                "input_ids": np.array([out], dtype=np.int64),
                "encoder_hidden_states": hidden,
                "encoder_attention_mask": mask,
            },
        )[0]
        assert logits.shape[-1] == len(inv), f"lebar logit {logits.shape[-1]} != ukuran kosakata {len(inv)}"
        row = logits[0, -1].copy()
        row[pad] = -np.inf
        nxt = int(row.argmax())
        if nxt == eos:
            break
        out.append(nxt)
    ids_out = out[1:]
    pieces = [inv.get(i, "") for i in ids_out if i not in (eos, pad) and inv.get(i) != "<unk>"]
    return src, ids_out, "".join(pieces).replace("▁", " ").strip()


def main():
    root, dest = sys.argv[1], sys.argv[2]
    result = []
    for d, sentences in KALIMAT.items():
        vocab, inv, enc, dec, sp = load(root, d)
        print(f"[{d}] ukuran kosakata = {len(inv)}, pad = {vocab['<pad>']}")
        for text in sentences:
            t0 = time.time()
            src, ids_out, out_text = translate(vocab, inv, enc, dec, sp, text)
            print(f"  {int((time.time() - t0) * 1000):5d} ms  {text}\n           -> {out_text}")
            result.append({"dir": d, "text": text, "src_ids": src, "out_ids": ids_out, "out_text": out_text})
    json.dump(result, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
