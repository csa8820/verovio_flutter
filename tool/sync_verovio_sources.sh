#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/third_party/verovio/data"
DST="$ROOT/assets/verovio_data"

if [[ ! -d "$SRC" ]]; then
  echo "missing source directory: $SRC" >&2
  exit 1
fi

rm -rf "$DST"
mkdir -p "$DST"
cp -R "$SRC/." "$DST/"

echo "synced verovio @ $(git -C "$ROOT/third_party/verovio" describe --tags --always)"
