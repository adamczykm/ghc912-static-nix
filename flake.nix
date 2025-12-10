{
  description = "Proof-of-concept: Static Haskell binary with GHC 9.12.2 and Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";

      # Import nixpkgs with different libc variants
      pkgs = import nixpkgs { inherit system; };
      pkgsMusl = pkgs.pkgsMusl;     # musl-based packages (required for static linking)
      pkgsStatic = pkgs.pkgsStatic; # Pre-configured static packages

      # GHC 9.12.2 with musl for static linking
      # Note: GHC 9.12.2 is only available in nixpkgs master as of 2025-12
      haskellPackages = pkgsMusl.haskell.packages.ghc9122;

      hsLib = pkgs.haskell.lib;

      # =========================================================================
      # Static C Libraries Configuration
      # =========================================================================
      # GHC 9.6+ introduced libdw (DWARF debugging) support, which requires:
      # - elfutils (provides libdw and libelf)
      # - Compression libraries that elfutils depends on (bzip2, xz, zstd)
      #
      # Reference: https://sigkill.dk/blog/2024-05-22-static-linking-on-nix-with-ghc96.html

      # Core libraries needed by GHC runtime
      gmpStatic = pkgsMusl.gmp6.override { withStatic = true; };
      libffiStatic = pkgsMusl.libffi.overrideAttrs (old: { dontDisableStatic = true; });
      zlibStatic = pkgsMusl.zlib.static;

      # NUMA support library
      numactlStatic = pkgsMusl.numactl.overrideAttrs (old: { dontDisableStatic = true; });

      # elfutils (provides libdw and libelf for DWARF debugging)
      elfutilsStatic = pkgsMusl.elfutils.overrideAttrs (old: { dontDisableStatic = true; });

      # Compression libraries required by elfutils
      # Use pkgsStatic for these as they already have static builds configured
      # Note: Use .out to get library files (.a), not just binaries
      bzip2Static = pkgsStatic.bzip2.out;
      xzStatic = pkgsStatic.xz.out;
      zstdStatic = pkgsStatic.zstd.out;

      # =========================================================================
      # Main Haskell Package
      # =========================================================================
      staticBinary = hsLib.overrideCabal
        (haskellPackages.callCabal2nix "ghc912-static-nix" ./. { })
        (old: {
          # Disable shared libraries to force static linking
          enableSharedExecutables = false;
          enableSharedLibraries   = false;

          configureFlags = (old.configureFlags or [ ]) ++ [
            # Primary static linking flags
            "--ghc-option=-optl=-static"
            "--ghc-option=-optl=-pthread"

            # Library directories for core GHC dependencies
            "--extra-lib-dirs=${gmpStatic}/lib"
            "--extra-lib-dirs=${libffiStatic}/lib"
            "--extra-lib-dirs=${numactlStatic}/lib"
            "--extra-lib-dirs=${zlibStatic}/lib"

            # Library directories for GHC 9.6+ libdw support
            "--extra-lib-dirs=${elfutilsStatic}/lib"
            "--extra-lib-dirs=${bzip2Static}/lib"
            "--extra-lib-dirs=${xzStatic}/lib"
            "--extra-lib-dirs=${zstdStatic}/lib"

            # Explicit linker flags for libdw transitive dependencies
            # GHC doesn't automatically link these, so we must specify them
            "--ghc-option=-optl=-lelf"   # from elfutils
            "--ghc-option=-optl=-lbz2"   # from bzip2
            "--ghc-option=-optl=-lz"     # from zlib
            "--ghc-option=-optl=-llzma"  # from xz
            "--ghc-option=-optl=-lzstd"  # from zstd
          ];
        });

    in {
      # =========================================================================
      # Package Outputs
      # =========================================================================
      packages.${system} = {
        ghc912-static-nix = staticBinary;
        default = staticBinary;
      };

      # =========================================================================
      # Development Shell
      # =========================================================================
      # Provides GHC, cabal, and essential tools for development
      # Usage: nix develop
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          haskellPackages.ghc
          pkgs.cabal-install
          pkgs.pkg-config
        ];

        shellHook = ''
          echo "Haskell development environment"
          echo "GHC version: $(ghc --version)"
          echo "Cabal version: $(cabal --version | head -1)"
          echo ""
          echo "Available commands:"
          echo "  cabal build    - Build the project"
          echo "  cabal run      - Run the executable"
          echo "  cabal test     - Run tests (if any)"
        '';
      };
    };
}
