# zip

Standalone build of [Info-ZIP zip](https://infozip.sourceforge.net/Zip.html).

[![CI](https://github.com/unpins/zip/actions/workflows/zip.yml/badge.svg)](https://github.com/unpins/zip/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

## Usage

Run a program with [unpin](https://github.com/unpins/unpin):

```bash
unpin zip -r out.zip dir/
unpin zip zipnote out.zip
```

To install the programs onto your PATH:

```bash
unpin install zip
```

`unpin install zip` also creates the `zipcloak`, `zipnote`, `zipsplit` commands.

## Build locally

```bash
nix build github:unpins/zip
./result/bin/zip -v
```

Or run directly:

```bash
nix run github:unpins/zip
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/zip/releases) page has standalone binaries for manual download.

## Build notes

- Info-ZIP ships four separate executables; they are post-linked into a single
  multicall `zip` binary (`zipcloak`, `zipnote`, `zipsplit` dispatch by
  `argv[0]`). Without an installed alias, run them as `zip zipnote …` etc.
- **ZIP64 / large files forced on.** Info-ZIP's `configure` detects large-file
  and 32-bit UID/GID support by *running* a probe, which can't run when
  cross-compiling — so those flags are set unconditionally (all targets have
  64-bit `off_t` and 32-bit ids).
- **Windows** is built with [Cosmopolitan](https://github.com/jart/cosmopolitan)
  rather than mingw: Info-ZIP's `unix/Makefile` is Unix-only (`ttyio.c` needs
  `<sys/ioctl.h>`), and its separate `win32` makefile is a different port.

## Man pages

The man pages for `zip`, `zipcloak`, `zipnote` and `zipsplit` are embedded in
the binary; read one with `unpin man zip`, e.g. `unpin man zip zipnote`.
