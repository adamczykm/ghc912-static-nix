#!/usr/bin/env bash
set -euo pipefail

echo ">>> Buduję projekt (Nix + GHC 9.12, static)..."
nix build .#lambda-test

echo ">>> Wynikowy binarek powinien być w ./result/bin/lambda-test"
ls -l result/bin || true
