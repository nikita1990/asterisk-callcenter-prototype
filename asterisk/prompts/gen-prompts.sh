#!/bin/sh
# Синтез подсказок IVR: espeak-ng -> sox (8 кГц, mono, 16 бит PCM — формат wav для Asterisk)
# usage: gen-prompts.sh prompts.txt out_dir
set -eu
in="$1"; out="$2"
mkdir -p "$out"
grep -v '^#' "$in" | grep -v '^$' | while IFS='|' read -r name lang text; do
    espeak-ng -v "$lang" -s 150 -w "/tmp/$name.raw.wav" "$text"
    sox "/tmp/$name.raw.wav" -r 8000 -c 1 -b 16 "$out/$name.wav" gain -n -3
    rm -f "/tmp/$name.raw.wav"
    echo "prompt: $name.wav"
done
