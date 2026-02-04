# Static Haskell Binary with GHC 9.12.2 and Nix

A minimal proof-of-concept demonstrating how to build fully statically linked Haskell executables using GHC 9.12.2 and Nix flakes. Supports both **x86_64** and **aarch64** (ARM64) targets, including cross-compilation for Raspberry Pi. The resulting binaries have no runtime dependencies and are ready for deployment to environments like AWS Lambda or bare-metal ARM devices.

## Why This Matters

Starting with GHC 9.6, the compiler includes support for DWARF debugging information via `libdw` (from elfutils), which introduces additional linking complexity. This project shows how to properly configure Nix to build static binaries with modern GHC versions, handling:

- **musl libc** instead of glibc (required for practical static linking)
- **Static versions of C libraries** (gmp, libffi, numactl, zlib)
- **elfutils and compression libraries** (bzip2, xz, zstd) required by GHC 9.6+ for libdw
- **Explicit linker flags** to resolve transitive dependencies

## Supported Targets

| Target | Build command | Use case |
|--------|-------------|----------|
| x86_64 (native) | `nix build` | Servers, AWS Lambda, x86 desktops |
| aarch64 (cross-compiled) | `nix build .#aarch64` | Raspberry Pi 5, ARM servers |

Both targets produce fully static binaries with zero runtime dependencies. The aarch64 binary is cross-compiled from x86_64 — no ARM hardware or emulation needed to build.

## Quick Start

### Build the static binary

```bash
# Native x86_64
nix build

# Cross-compile for ARM64 (Raspberry Pi 5, etc.)
nix build .#aarch64
```

The binary will be available at `result/bin/ghc912-static-nix`.

### Verify it's statically linked

```bash
file result/bin/ghc912-static-nix
# x86_64: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, stripped
# aarch64: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked, stripped

ldd result/bin/ghc912-static-nix
# Output: not a dynamic executable
```

### Test the binary

```bash
echo '{"test": "hello"}' | result/bin/ghc912-static-nix
# Output: {"message":"Hello from statically linked Haskell!","input":"{\"test\": \"hello\"}\n"}
```

### Deploy to Raspberry Pi

Copy the aarch64 binary directly to a Raspberry Pi 5 — no Haskell toolchain or libraries needed on the device:

```bash
nix build .#aarch64
scp result/bin/ghc912-static-nix pi@raspberrypi:~/
ssh pi@raspberrypi ./ghc912-static-nix
```

### Package for AWS Lambda

```bash
./scripts/package-lambda.sh
```

This creates `dist/ghc912-static-nix.zip` ready to deploy to AWS Lambda with runtime `provided.al2`.

## Project Structure

```
.
├── flake.nix                    # Nix flake with GHC 9.12.2 and static linking configuration
├── ghc912-static-nix.cabal     # Minimal Cabal project
├── app/
│   └── Main.hs                 # Simple JSON echo program
├── scripts/
│   ├── dev-shell.sh           # Enter development shell
│   ├── build.sh               # Build static binary
│   └── package-lambda.sh      # Package for AWS Lambda
└── .gitignore
```

## How It Works

### The Challenge

GHC 9.6+ introduced libdw (DWARF debugging) support, which requires:
1. elfutils library
2. Compression libraries that elfutils depends on (bzip2, xz, zstd)
3. Explicit linker flags because GHC doesn't automatically link transitive dependencies

### The Solution

Our `flake.nix` handles this by:

1. **Using nixpkgs master** to get GHC 9.12.2
   ```nix
   inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";
   ```

2. **Building with pkgsMusl** for musl-based static linking
   ```nix
   haskellPackages = pkgsMusl.haskell.packages.ghc9122;
   ```

3. **Providing static versions of C libraries**
   - `gmp6.override { withStatic = true; }` - GMP with static libs enabled
   - `libffi.overrideAttrs (old: { dontDisableStatic = true; })` - prevent disabling static libs
   - `pkgsStatic.{bzip2,xz,zstd}.out` - pre-built static compression libraries

4. **Adding explicit linker flags** for libdw dependencies
   ```nix
   "--ghc-option=-optl=-lelf"
   "--ghc-option=-optl=-lbz2"
   "--ghc-option=-optl=-lz"
   "--ghc-option=-optl=-llzma"
   "--ghc-option=-optl=-lzstd"
   ```

### Cross-compilation for ARM64

The ARM64 build uses `pkgsCross.aarch64-multiplatform-musl` to cross-compile from x86_64. A shared `mkStaticBinary` helper is parameterized over the target-specific packages, keeping the configuration DRY.

Key detail: for cross-compiled elfutils, the `.out` output must be used explicitly — the default output resolves to `-bin` which only contains binaries, not the static libraries (`libelf.a`, `libdw.a`) needed at link time.

### Key Configuration

The core of the static linking setup in `flake.nix`:

```nix
lambdaTest = hsLib.overrideCabal
  (haskellPackages.callCabal2nix "ghc912-static-nix" ./. { })
  (old: {
    enableSharedExecutables = false;
    enableSharedLibraries   = false;
    configureFlags = (old.configureFlags or [ ]) ++ [
      "--ghc-option=-optl=-static"
      "--ghc-option=-optl=-pthread"
      # ... library directories ...
      # ... explicit linker flags ...
    ];
  });
```

## Development

Enter the development shell with GHC and cabal:

```bash
./scripts/dev-shell.sh
```

Inside the shell you can use standard Cabal commands:

```bash
cabal build
cabal run ghc912-static-nix
```

## Customization

To adapt this for your project:

1. **Rename the project**: Update `name` in `ghc912-static-nix.cabal` and adjust `flake.nix` accordingly
2. **Add dependencies**: Add Haskell packages to `build-depends` in the `.cabal` file
3. **Modify the application**: Edit `app/Main.hs` with your logic
4. **Rebuild**: Run `./scripts/build.sh`

## Binary Size

The resulting binary is approximately 3.1 MB, which is typical for statically linked Haskell programs with GHC's runtime system included.

## References

This project builds on knowledge from several excellent resources:

- [Static linking on Nix with GHC 9.6](https://sigkill.dk/blog/2024-05-22-static-linking-on-nix-with-ghc96.html) - Explains libdw requirements for GHC 9.6+
- [CS-SYD: Getting your Haskell executable statically linked with Nix](https://cs-syd.eu/posts/2024-04-20-static-linking-haskell-nix) - General Nix static linking approach
- [nh2/static-haskell-nix](https://github.com/nh2/static-haskell-nix) - Comprehensive static Haskell builds

## Troubleshooting

### Build fails with "cannot find -lgmp" or similar

This usually means a static library isn't being found. Check that:
1. The library is in the `let` bindings (e.g., `gmpStatic`)
2. It's added to `--extra-lib-dirs=`
3. If needed, add an explicit linker flag `--ghc-option=-optl=-l<name>`

### "bad optional access" error

This means a Nix attribute doesn't exist. Common causes:
- GHC version not available in your nixpkgs version
- Typo in attribute name
- Package doesn't support the override you're trying

### Binary isn't actually static

Verify with `ldd result/bin/ghc912-static-nix`. If it shows libraries:
- Check that `--ghc-option=-optl=-static` is present
- Ensure `enableSharedExecutables = false`
- Verify you're using `pkgsMusl` not regular `pkgs`

## License

MIT

## Contributing

This is a proof-of-concept project. Feel free to fork and adapt for your needs. Issues and PRs welcome!
