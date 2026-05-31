# Info-ZIP `zip` ships four separate executables — zip (create/update),
# zipcloak (encrypt entries), zipnote (edit comments) and zipsplit (split an
# archive). To honour the unpins one-pkg-one-bin rule we post-link them into a
# single multicall binary at $out/bin/zip; `lib.withAliases` then embeds the
# applet names as an UNPIN_META block so unpin's installer recreates the
# argv[0] shims.
#
# Why a post-link route (no source patch): the utilities are deliberately
# separate programs that share function NAMES. zip links the regular objects
# (zipfile.o, fileio.o, util.o, crypt.o, …); the utilities link the `-DUTIL`
# variants compiled from the same sources (zipfile_.o, fileio_.o, util_.o …)
# plus globals.o. Both define `readzipfile`, `zfwrite`, … so linking all four
# object sets into one binary collides on dozens of symbols. The collisions
# are cross-tool, and zip's own `main` objects CALL those helpers across
# object boundaries, so srt-style "localize the duplicates" would leave the
# refs undefined. Instead we use the ld-r + prefix-rename recipe
# (cf. util-linux/e2fsprogs): per tool, `ld -r` its object set into one
# partial object, then `objcopy --redefine-sym` renames `main` → <tool>_main
# and every other strong defined global `foo` → <tool>__foo. objcopy rewrites
# the definition AND every relocation that references it, so each tool's
# partial is self-contained and the four no longer collide. A dispatcher.c
# (basename(argv[0]) → <tool>_main) drives the final link.
#
# Object sets come straight from unix/Makefile's OBJZ/OBJN/OBJC/OBJS; the only
# configure-variable pieces (OCRCU8/OCRCTB — Unicode CRC table selection — and
# LFLAGS1/LFLAGS2/OBJA/LIB_BZ) are read from the `flags` file unix/configure
# writes, so the recipe tracks whatever the build actually configured.
#
# Shared by the native `build` (pkgsStatic ELF / Mach-O) and the `windowsBuild`
# (Cosmopolitan APE) paths.
{ lib }:
{ pkgs, zip }:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin or false;
  isWindows = pkgs.stdenv.hostPlatform.isWindows or false;

  # The four tools and the unix/Makefile variable each one links.
  #   zip      : $(OBJZ) $(OBJI) $(OBJA) $(LIB_BZ)
  #   zipnote  : $(OBJN)
  #   zipcloak : $(OBJC)
  #   zipsplit : $(OBJS)
  # with OBJU = zipfile_.o fileio_.o util_.o globals.o unix_.o $(OCRCU8).
  multicall = zip.overrideAttrs (old: {
    pname = "zip-multi";
    outputs = [ "out" ];
    # nixpkgs' zip installs via `make install INSTALL=cp`; we replace that with
    # our own installPhase (multicall binary + applet symlinks + man), so drop
    # the upstream install hooks.
    installFlags = [ ];

    # Force Large-File / ZIP64 support and modern 32-bit UID/GID on every
    # target. unix/configure detects both by COMPILING AND RUNNING a probe
    # (`./conftest`), which fails silently under cross-compilation (the target
    # binary can't run on the build host) → zip would quietly ship without
    # ZIP64 (no >4 GB / >65535-entry archives) and with obsolete 16-bit
    # UID/GID. All our targets (musl, darwin, cosmo) have 64-bit off_t and
    # 32-bit ids, so define these unconditionally; on hosts where the probe
    # does run it sets the same macros, so this is a no-op there.
    NIX_CFLAGS_COMPILE = (old.NIX_CFLAGS_COMPILE or "")
      + " -DLARGE_FILE_SUPPORT -DUIDGID_NOT_16BIT";

    postBuild = (old.postBuild or "") + ''
      set -e
      mkdir -p multicall

      # unix/configure wrote the resolved build vars here.
      OCRCU8=""; OCRCTB=""; OBJA=""; LIB_BZ=""; LFLAGS1=""; LFLAGS2=""
      if [ -f flags ]; then eval "$(cat flags)"; fi

      OBJU="zipfile_.o fileio_.o util_.o globals.o unix_.o $OCRCU8"
      declare -A TOOLOBJS
      TOOLOBJS[zip]="zip.o zipfile.o zipup.o fileio.o util.o globals.o crypt.o ttyio.o unix.o crc32.o zbz2err.o deflate.o trees.o $OBJA $LIB_BZ"
      TOOLOBJS[zipnote]="zipnote.o $OBJU"
      TOOLOBJS[zipcloak]="zipcloak.o $OBJU $OCRCTB crypt_.o ttyio.o"
      TOOLOBJS[zipsplit]="zipsplit.o $OBJU"
      TOOLS="zip zipnote zipcloak zipsplit"

      # Mach-O leads C symbols with '_'; detect once from zip.o's `main`.
      if $NM --defined-only zip.o 2>/dev/null | awk '$3=="_main"{f=1} END{exit !f}'; then
        up=_
      else
        up=""
      fi

      for t in $TOOLS; do
        objs="''${TOOLOBJS[$t]}"
        # Drop empty tokens and any object the configure didn't produce
        # (e.g. LIB_BZ when bzip2 is off).
        real=""
        for o in $objs; do [ -f "$o" ] && real="$real $o"; done

        # Partial-link the tool's object set into one relocatable object.
        $LD -r -o "multicall/$t.o" $real

        # Build the redefine map: main → <t>_main, every other strong defined
        # global foo → <t>__foo. Skip weak/COMDAT (W/V) so libgcc/COMDAT dedup
        # still resolves them, and skip names with a '.' (compiler thunks like
        # __x86.get_pc_thunk.bx — not valid identifiers, must stay shared).
        $NM --defined-only "multicall/$t.o" 2>/dev/null \
          | awk -v t="$t" -v up="$up" '
              $2 ~ /^[A-TX-Z]$/ && $2 != "W" && $2 != "V" {
                sym = $3
                core = sym
                if (up != "" && index(core, up) == 1) core = substr(core, 2)
                if (index(core, ".") != 0) next
                if (core !~ /^[A-Za-z_][A-Za-z0-9_]*$/) next
                if (core == "main") print sym " " up t "_main"
                else                print sym " " up t "__" core
              }' | sort -u > "multicall/$t.redef"
        [ -s "multicall/$t.redef" ] && \
          $OBJCOPY --redefine-syms="multicall/$t.redef" "multicall/$t.o"
      done

      # Dispatcher: basename(argv[0]) → <tool>_main, with a `zip <applet>`
      # fallback so the bare binary stays callable and survives a rename
      # (CI smoke copies it to smoke.exe).
      {
        echo '#include <string.h>'
        echo '#include <stdio.h>'
        for t in $TOOLS; do echo "int ''${t}_main(int, char **);"; done
        echo 'struct applet { const char *name; int (*fn)(int, char **); };'
        echo 'static const struct applet applets[] = {'
        for t in $TOOLS; do echo "    {\"$t\", ''${t}_main},"; done
        cat <<'CBODY'
    {0, 0}
};
static void base_of(char *dst, size_t cap, const char *src) {
    const char *p = src, *s;
    s = strrchr(p, '/'); if (s) p = s + 1;
#ifdef _WIN32
    s = strrchr(p, '\\'); if (s) p = s + 1;
#endif
    size_t n = strlen(p); if (n >= cap) n = cap - 1;
    memcpy(dst, p, n); dst[n] = 0;
    if (n > 4 && strcmp(dst + n - 4, ".exe") == 0) dst[n - 4] = 0;
}
static int usage(const char *a0) {
    fprintf(stderr, "zip: multicall binary; usage: %s <applet> [args]\n", a0);
    fprintf(stderr, "applets:");
    for (const struct applet *a = applets; a->name; a++)
        fprintf(stderr, " %s", a->name);
    fprintf(stderr, "\n");
    return 1;
}
int main(int argc, char **argv) {
    char base[64];
    const char *a0 = (argc > 0 && argv[0]) ? argv[0] : "zip";
    base_of(base, sizeof base, a0);
    if (strcmp(base, "zip") != 0) {
        for (const struct applet *a = applets; a->name; a++)
            if (strcmp(base, a->name) == 0) return a->fn(argc, argv);
    }
    /* argv[0] is `zip` (or unknown): allow `zip <applet> [args]`, else run zip. */
    if (argc >= 2) {
        base_of(base, sizeof base, argv[1]);
        for (const struct applet *a = applets; a->name; a++)
            if (strcmp(base, a->name) == 0) return a->fn(argc - 1, argv + 1);
    }
    return zip_main(argc, argv);
}
CBODY
      } > multicall/dispatcher.c
      $CC -O2 -c -o multicall/dispatcher.o multicall/dispatcher.c

      # Final link: reuse the configure-resolved link flags; the pkgsStatic /
      # cosmo cc-wrapper supplies -static. One pass — the rename made every
      # partial self-contained.
      $CC $LFLAGS1 \
        multicall/zip.o multicall/zipnote.o multicall/zipcloak.o multicall/zipsplit.o \
        multicall/dispatcher.o \
        $LFLAGS2 -o multicall/zip
      [ -f multicall/zip ] || mv multicall/zip.exe multicall/zip
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/share/man/man1"
      install -m755 multicall/zip "$out/bin/zip"
      for a in zipcloak zipnote zipsplit; do ln -s zip "$out/bin/$a"; done
      for m in zip zipcloak zipnote zipsplit; do
        [ -f "man/$m.1" ] && cp "man/$m.1" "$out/share/man/man1/$m.1"
      done
      runHook postInstall
    '';
  });

  aliased = lib.withAliases pkgs
    {
      primary = "zip";
      aliasesFromSymlinksIn = "bin";
    }
    multicall;
in
if isWindows
then aliased.overrideAttrs (o: {
  postFixup = (o.postFixup or "") + ''
    [ -f "$out/bin/zip" ] && mv "$out/bin/zip" "$out/bin/zip.exe"
  '';
})
else aliased
