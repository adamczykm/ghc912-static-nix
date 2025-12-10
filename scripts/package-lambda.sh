#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo ">>> Buduję projekt..."
nix build "$ROOT"#lambda-test

OUT_DIR="$ROOT/dist"
mkdir -p "$OUT_DIR"

echo ">>> Kopiuję binarkę jako 'bootstrap' dla AWS Lambda..."
cp "$ROOT/result/bin/lambda-test" "$OUT_DIR/bootstrap"
chmod +x "$OUT_DIR/bootstrap"

echo ">>> Tworzę ZIP do wrzucenia do Lambda..."
(
  cd "$OUT_DIR"
  zip -9 lambda-test.zip bootstrap
)

echo ">>> Gotowe:"
ls -lh "$OUT_DIR"/lambda-test.zip
