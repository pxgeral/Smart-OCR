#!/usr/bin/env bash
# Mengunduh model terjemahan offline (OPUS-MT oleh Helsinki-NLP, versi ONNX int8
# oleh Xenova) ke assets/models/<arah>/ agar ikut terkemas di APK.
# Dipakai CI; aman dijalankan ulang (berkas yang sudah ada dilewati).
set -euo pipefail
cd "$(dirname "$0")/.."
BASE=https://huggingface.co/Xenova

get() { # url tujuan ukuran-minimum-byte
  if [ -f "$2" ] && [ "$(stat -c%s "$2")" -ge "$3" ]; then
    echo "sudah ada: $2"; return
  fi
  curl -fL --retry 4 --retry-delay 5 --connect-timeout 30 -o "$2.part" "$1"
  local size; size=$(stat -c%s "$2.part")
  if [ "$size" -lt "$3" ]; then echo "ukuran janggal ($size byte): $2" >&2; exit 1; fi
  mv "$2.part" "$2"
}

for d in id-en en-id; do
  out="assets/models/$d"; mkdir -p "$out"
  repo="$BASE/opus-mt-$d/resolve/main"
  get "$repo/onnx/encoder_model_quantized.onnx" "$out/encoder.onnx" 30000000
  get "$repo/onnx/decoder_model_quantized.onnx" "$out/decoder.onnx" 30000000
  get "$repo/vocab.json" "$out/vocab.json" 500000
  get "$repo/source.spm" "$out/source.spm" 300000
done
echo "== ringkasan"; ls -la assets/models/*/
# kunci isi model: gagal bila berkas di sumber berubah atau rusak
sha256sum -c tool/model.sha256
