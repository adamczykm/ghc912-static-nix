#!/usr/bin/env bash
# Build the static Haskell binary using Nix
set -euo pipefail

echo ">>> Building static binary (Nix + GHC 9.12.2)..."
nix build .#ghc912-static-nix

echo ">>> Binary available at ./result/bin/ghc912-static-nix"
ls -lh result/bin/ghc912-static-nix

echo ""
echo ">>> Verifying static linking..."
LDD_OUTPUT=$(ldd result/bin/ghc912-static-nix 2>&1 || true)
if echo "$LDD_OUTPUT" | grep -q "not a dynamic executable"; then
    echo "✓ Binary is statically linked"
else
    echo "✗ Warning: Binary may have dynamic dependencies"
    echo "$LDD_OUTPUT"
fi
