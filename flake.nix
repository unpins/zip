{
  description = "Info-ZIP zip as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # Info-ZIP zip is four separate executables (zip + zipcloak/zipnote/zipsplit);
  # ./multicall.nix post-links them into one `zip` binary with the helpers as
  # argv[0]-dispatch UNPIN_META aliases. Windows goes through Cosmopolitan: the
  # vanilla mingw cross fails because Info-ZIP's unix/Makefile is Unix-only
  # (ttyio.c needs <sys/ioctl.h>), and the official win32 makefile is a separate
  # port; Cosmopolitan libc provides the Unix headers so the unix path builds.
  outputs = { self, unpins-lib }:
    let ulib = unpins-lib.lib; in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "zip";
      # `zip -v` prints the Info-ZIP banner on every platform.
      smoke = [ "-v" ];
      smokePattern = "Info-ZIP";

      # Build via the unpin-llvm engine + emit a bitcode multicall module. The
      # standalone self-folds zip + zipnote/zipcloak/zipsplit into one
      # dispatcher binary from the captured module.bc; the old ld-r/objcopy
      # fold in ./multicall.nix can't run on the engine's -flto bitcode objects,
      # so it's reserved for the Windows (cosmo) path. Info-ZIP builds four
      # separate real executables, so we list all four programs.
      engine = "unpin-llvm";
      multicall = {
        programs = [
          { name = "zip"; }
          { name = "zipnote"; }
          { name = "zipcloak"; }
          { name = "zipsplit"; }
        ];
      };
      # linux + darwin both self-fold through the engine (bitcode module), like
      # coreutils — no hand-rolled ld-r/objcopy fold (that recipe is ELF-only
      # and doesn't port to Mach-O). Windows still uses ./multicall.nix. zip
      # builds no shared lib, so no --disable-shared dance is needed on darwin.
      build = pkgs: pkgs.pkgsStatic.zip;
      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; zip = (ulib.cosmoStaticCross pkgs).zip; };
    };
}
