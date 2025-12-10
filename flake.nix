{
  description = "Minimalny testowy projekt Haskell + Nix + static linking";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";

      # Używamy pkgsMusl dla łatwiejszego statycznego linkowania
      pkgs = import nixpkgs { inherit system; };
      pkgsMusl = pkgs.pkgsMusl;
      pkgsStatic = pkgs.pkgsStatic;

      # GHC 9.12.2 z musl dla statycznego linkowania
      haskellPackages = pkgsMusl.haskell.packages.ghc9122;

      hsLib = pkgs.haskell.lib;

      # Statyczne wersje bibliotek C
      # GHC 9.6+ wymaga libdw/elfutils + biblioteki kompresji (https://sigkill.dk/blog/2024-05-22-static-linking-on-nix-with-ghc96.html)
      # Dla bibliotek bez .static używamy pkgsStatic lub overrideAttrs
      gmpStatic = pkgsMusl.gmp6.override { withStatic = true; };
      libffiStatic = pkgsMusl.libffi.overrideAttrs (old: { dontDisableStatic = true; });
      zlibStatic = pkgsMusl.zlib.static;
      numactlStatic = pkgsMusl.numactl.overrideAttrs (old: { dontDisableStatic = true; });
      elfutilsStatic = pkgsMusl.elfutils.overrideAttrs (old: { dontDisableStatic = true; });
      # Biblioteki kompresji z pkgsStatic (mają już statyczne wersje)
      # Używamy .out aby dostać pliki bibliotek (.a), nie binarne
      bzip2Static = pkgsStatic.bzip2.out;
      xzStatic = pkgsStatic.xz.out;
      zstdStatic = pkgsStatic.zstd.out;

      # Główny pakiet Haskellowy – będzie zbudowany jako statyczny binarek
      lambdaTest = hsLib.overrideCabal
        (haskellPackages.callCabal2nix "lambda-test" ./. { })
        (old: {
          enableSharedExecutables = false;
          enableSharedLibraries   = false;
          # Statyczne linkowanie + statyczne biblioteki C
          configureFlags = (old.configureFlags or [ ]) ++ [
            "--ghc-option=-optl=-static"
            "--ghc-option=-optl=-pthread"
            "--extra-lib-dirs=${gmpStatic}/lib"
            "--extra-lib-dirs=${libffiStatic}/lib"
            "--extra-lib-dirs=${numactlStatic}/lib"
            "--extra-lib-dirs=${zlibStatic}/lib"
            # GHC 9.6+ potrzebuje libdw/elfutils + biblioteki kompresji
            "--extra-lib-dirs=${elfutilsStatic}/lib"
            "--extra-lib-dirs=${bzip2Static}/lib"
            "--extra-lib-dirs=${xzStatic}/lib"
            "--extra-lib-dirs=${zstdStatic}/lib"
            # Explicitne flagi linkowania dla libdw dependencies
            "--ghc-option=-optl=-lelf"
            "--ghc-option=-optl=-lbz2"
            "--ghc-option=-optl=-lz"
            "--ghc-option=-optl=-llzma"
            "--ghc-option=-optl=-lzstd"
          ];
        });
    in {
      # `nix build .#lambda-test`
      packages.${system} = {
        lambda-test = lambdaTest;
        default = lambdaTest;
      };

      # shell deweloperski: GHC + cabal + narzędzia
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          haskellPackages.ghc
          pkgs.cabal-install
          pkgs.pkg-config
        ];
      };
    };
}
