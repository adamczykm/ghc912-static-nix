#!/usr/bin/env bash
# Enter the Nix development shell with GHC and Cabal
set -euo pipefail

nix develop .#default
