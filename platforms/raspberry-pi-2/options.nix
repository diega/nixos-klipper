{ lib, ... }:

{
  options.nixosKlipper = {
    # Extra lines for the GPU firmware's config.txt (used by camera.nix).
    boot.extraConfigTxt = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra lines for config.txt.";
    };

    camera.enable = lib.mkEnableOption ''
      the CSI camera (ov5647) through the GPU's old stack (start_x=1) with µStreamer
      (not libcamera/camera-streamer)'';

    build.ccache.enable = lib.mkEnableOption ''
      build the kernel with ccache. Nix caches whole derivations, not objects: changing ONE kernel
      option rebuilds it from scratch. With ccache only what changed is rebuilt. It REQUIRES that the
      builder has the cache directory (see `build.ccache.dir`); if it does not exist, the build fails
      with a clear message. The first time it compiles everything anyway (it fills the cache)'';

    build.ccache.dir = lib.mkOption {
      type = lib.types.str;
      default = "/var/cache/ccache";
      description = ''
        Cache directory INSIDE the builder (the nix-darwin VM). It has to exist there, be 0770 root:nixbld
        and be in `nix.settings.extra-sandbox-paths`; `programs.ccache.enable` in the builder configuration
        (nix-darwin-macross repo) does that.
      '';
    };
  };
}
