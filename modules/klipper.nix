{ config, lib, pkgs, fluidd-config, sources, ... }:

{
  # Klipper v0.14.0 (flake input `klipper-src`; nixpkgs 26.05 ships a March commit). The Python environment is nixpkgs' plus `msgspec`, which v0.14.0 adds. Notes on the overrideAttrs of a `rec` recipe: `sourceRoot` and `.version` are computed from the ORIGINAL `src`/`version`, which is why sourceRoot is rewritten by hand and the .version file is written in postInstall. (On 32-bit ARM, modules/armv7l.nix drops numpy and matplotlib.)
  nixpkgs.overlays = [
    (final: prev: {
      klipper = (prev.klipper.override { extraPythonPackages = p: [ p.msgspec ]; }).overrideAttrs (old: {
        version = "0.14.0";
        src = sources.klipper-src;
        sourceRoot = "source/klippy";
        postInstall = (old.postInstall or "") + ''
          echo "0.14.0-NixOS" > $out/lib/klipper/.version
        '';
      });
    })
  ];

  services.klipper = {
    enable = true;
    user = "klipper";
    group = "klipper";
    # printer.cfg comes from printer.nix; the existing SAVE_CONFIG block is kept when rebuilding.
    mutableConfig = false;
    logFile = "/var/lib/klipper/klippy.log";
  };

  users.users.klipper = {
    isSystemUser = true;
    group = "klipper";
    extraGroups = [ "dialout" ];
  };
  users.groups.klipper = { };

  systemd.tmpfiles.rules = [
    "d /var/lib/klipper 0775 klipper klipper -"
    # `[include fluidd.cfg]` (printer.nix) resolves relative to printer.cfg. The module writes printer.cfg with builtins.toFile, which does not accept store paths, so it is linked here.
    "L+ /var/lib/klipper/fluidd.cfg - - - - ${fluidd-config}/fluidd.cfg"
  ];
}
