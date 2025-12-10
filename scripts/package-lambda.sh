#!/usr/bin/env bash
# Package the static binary for AWS Lambda deployment
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo ">>> Building static binary..."
nix build "$ROOT"#ghc912-static-nix

OUT_DIR="$ROOT/dist"
mkdir -p "$OUT_DIR"

echo ">>> Copying binary as 'bootstrap' for AWS Lambda..."
cp "$ROOT/result/bin/ghc912-static-nix" "$OUT_DIR/bootstrap"
chmod +x "$OUT_DIR/bootstrap"

echo ">>> Creating deployment ZIP..."
(
  cd "$OUT_DIR"
  zip -9 ghc912-static-nix.zip bootstrap
)

echo ""
echo ">>> Deployment package ready:"
ls -lh "$OUT_DIR"/ghc912-static-nix.zip
echo ""
echo "Upload this ZIP to AWS Lambda with runtime: provided.al2"
