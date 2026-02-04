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

      # Cross-compilation target for ARM64 with musl (static linking)
      pkgsCrossAarch64 = pkgs.pkgsCross.aarch64-multiplatform-musl;

      # GHC 9.12.2 with musl for static linking (native x86_64)
      # Note: GHC 9.12.2 is only available in nixpkgs master as of 2025-12
      haskellPackages = pkgsMusl.haskell.packages.ghc9122;

      # GHC 9.12.2 cross-compiler for ARM64 with musl
      haskellPackagesCrossAarch64 = pkgsCrossAarch64.haskell.packages.ghc9122;

      hsLib = pkgs.haskell.lib;

      # =========================================================================
      # Static C Libraries Configuration (x86_64)
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
      # Static C Libraries Configuration (ARM64 cross-compilation)
      # =========================================================================
      # Use pkgsStatic from the cross-compilation toolchain for proper static libs
      pkgsCrossAarch64Static = pkgsCrossAarch64.pkgsStatic;

      gmpStaticAarch64 = pkgsCrossAarch64.gmp6.override { withStatic = true; };
      libffiStaticAarch64 = pkgsCrossAarch64.libffi.overrideAttrs (old: { dontDisableStatic = true; });
      zlibStaticAarch64 = pkgsCrossAarch64.zlib.static;

      # NUMA support library for ARM64
      numactlStaticAarch64 = pkgsCrossAarch64.numactl.overrideAttrs (old: { dontDisableStatic = true; });

      # elfutils for ARM64 (provides libdw and libelf)
      # The musl cross toolchain already builds static libraries (libelf.a, libdw.a)
      # Must use .out to get the library files, not the default -bin output
      elfutilsStaticAarch64 = pkgsCrossAarch64.elfutils.out;

      # Compression libraries for ARM64 - use pkgsStatic for pre-configured static builds
      bzip2StaticAarch64 = pkgsCrossAarch64Static.bzip2.out;
      xzStaticAarch64 = pkgsCrossAarch64Static.xz.out;
      zstdStaticAarch64 = pkgsCrossAarch64Static.zstd.out;

      # =========================================================================
      # Helper function to create static binary configuration
      # =========================================================================
      mkStaticBinary = { hsPkgs, gmp, libffi, numactl, zlib, elfutils, bzip2, xz, zstd }:
        hsLib.overrideCabal
          (hsPkgs.callCabal2nix "ghc912-static-nix" ./. { })
          (old: {
            # Disable shared libraries to force static linking
            enableSharedExecutables = false;
            enableSharedLibraries   = false;

            configureFlags = (old.configureFlags or [ ]) ++ [
              # Primary static linking flags
              "--ghc-option=-optl=-static"
              "--ghc-option=-optl=-pthread"

              # Library directories for core GHC dependencies
              "--extra-lib-dirs=${gmp}/lib"
              "--extra-lib-dirs=${libffi}/lib"
              "--extra-lib-dirs=${numactl}/lib"
              "--extra-lib-dirs=${zlib}/lib"

              # Library directories for GHC 9.6+ libdw support
              "--extra-lib-dirs=${elfutils}/lib"
              "--extra-lib-dirs=${bzip2}/lib"
              "--extra-lib-dirs=${xz}/lib"
              "--extra-lib-dirs=${zstd}/lib"

              # Explicit linker flags for libdw transitive dependencies
              # GHC doesn't automatically link these, so we must specify them
              "--ghc-option=-optl=-lelf"   # from elfutils
              "--ghc-option=-optl=-lbz2"   # from bzip2
              "--ghc-option=-optl=-lz"     # from zlib
              "--ghc-option=-optl=-llzma"  # from xz
              "--ghc-option=-optl=-lzstd"  # from zstd
            ];
          });

      # =========================================================================
      # Main Haskell Package (x86_64)
      # =========================================================================
      staticBinary = mkStaticBinary {
        hsPkgs = haskellPackages;
        gmp = gmpStatic;
        libffi = libffiStatic;
        numactl = numactlStatic;
        zlib = zlibStatic;
        elfutils = elfutilsStatic;
        bzip2 = bzip2Static;
        xz = xzStatic;
        zstd = zstdStatic;
      };

      # =========================================================================
      # Cross-compiled Haskell Package (ARM64)
      # =========================================================================
      staticBinaryAarch64 = mkStaticBinary {
        hsPkgs = haskellPackagesCrossAarch64;
        gmp = gmpStaticAarch64;
        libffi = libffiStaticAarch64;
        numactl = numactlStaticAarch64;
        zlib = zlibStaticAarch64;
        elfutils = elfutilsStaticAarch64;
        bzip2 = bzip2StaticAarch64;
        xz = xzStaticAarch64;
        zstd = zstdStaticAarch64;
      };

    in {
      # =========================================================================
      # Package Outputs
      # =========================================================================
      packages.${system} = {
        ghc912-static-nix = staticBinary;
        default = staticBinary;

        # Cross-compiled ARM64 binary (built on x86_64)
        aarch64 = staticBinaryAarch64;
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
          echo ""
          echo "Cross-compilation:"
          echo "  nix build .#aarch64  - Build static ARM64 binary"
        '';
      };
    };
}
