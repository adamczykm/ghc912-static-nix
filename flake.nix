{
  description = "Minimalny testowy projekt Haskell + Nix + static linking (GHC 9.12)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";

      # Bazujemy na musl, żeby dało się łatwiej linkować statycznie
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (final: prev: {
            haskellPackages = prev.pkgsMusl.haskell.packages.ghc912;
          })
        ];
      };

      hsLib = pkgs.haskell.lib;

      # Główny pakiet Haskellowy – będzie zbudowany jako statyczny binarek
      lambdaTest = hsLib.overrideCabal
        (pkgs.haskellPackages.callCabal2nix "lambda-test" ./. { })
        (old: {
          enableSharedExecutables = false;
          enableSharedLibraries   = false;
          # Statyczne linkowanie + dopinanie statycznych libów C
          configureFlags = (old.configureFlags or [ ]) ++ [
            "--ghc-option=-optl=-static"
            "--ghc-option=-optl=-pthread"
            # poniżej mogą wymagać dopasowania do konkretnej wersji nixpkgs
            "--extra-lib-dirs=${pkgs.zlib.static}/lib"
            "--extra-lib-dirs=${pkgs.gmp6.override { withStatic = true; }}/lib"
            "--extra-lib-dirs=${pkgs.libffi.overrideAttrs (o: { dontDisableStatic = true; })}/lib"
            "--extra-lib-dirs=${pkgs.ncurses.override { enableStatic = true; }}/lib"
          ];
        });
    in {
      # `nix build .#lambda-test`
      packages.${system}.lambda-test = lambdaTest;
      packages.${system}.default = lambdaTest;

      # shell deweloperski: GHC + cabal + narzędzia
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.haskellPackages.ghc
          pkgs.cabal-install
          pkgs.pkg-config
          pkgs.zlib.static
          pkgs.gmp6
          pkgs.libffi
          pkgs.ncurses
        ];
      };
    };
}
