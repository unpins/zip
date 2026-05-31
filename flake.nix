{
  description = "Standalone build of Info-ZIP zip";

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
      build = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; zip = pkgs.pkgsStatic.zip; };
      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; zip = (ulib.cosmoStaticCross pkgs).zip; };
    };
}
