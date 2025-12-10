#!/usr/bin/env bash
set -euo pipefail

# Wskakujesz w shell z GHC/cabal itd.
nix develop .#default
