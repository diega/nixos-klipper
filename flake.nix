{
  description = "NixOS for an Ender 3 running Klipper: Raspberry Pi 2 B (armv7l), SPI screen and optional camera";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Only to reuse the Raspberry Pi kernel recipe (raspberry-pi/common/kernel.nix).
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    # Fluidd macros (PAUSE/RESUME/CANCEL_PRINT...), included from printer.cfg as `[include fluidd.cfg]`.
    fluidd-config = {
      url = "github:fluidd-core/fluidd-config/v1.2.1";
      flake = false;
    };

    # Versions of the stack's components, pinned by tag. nixpkgs 26.05 ships older versions (Klipper from March, Moonraker 0.10.0, KlipperScreen 0.4.5, Fluidd 1.36); here the published releases are used. The flake.lock stores the hashes. To bump one:
    #   nix flake lock --override-input klipper-src github:Klipper3d/klipper/vX.Y.Z
    klipper-src = {
      url = "github:Klipper3d/klipper/v0.14.0";
      flake = false;
    };
    moonraker-src = {
      url = "github:Arksine/moonraker/v0.11.0";
      flake = false;
    };
    klipperscreen-src = {
      url = "github:KlipperScreen/KlipperScreen/v0.4.7";
      flake = false;
    };
    # Prebuilt Fluidd release (static web app); building it with npm is not viable on armv7l.
    fluidd-release = {
      url = "tarball+https://github.com/fluidd-core/fluidd/releases/download/v1.38.1/fluidd.zip";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixos-hardware, fluidd-config, klipper-src, moonraker-src, klipperscreen-src, fluidd-release, ... }:
    let
      sources = { inherit klipper-src moonraker-src klipperscreen-src fluidd-release; };
    in
    {
      # Reusable modules. A machine is built by combining one of each kind, or with the combined module below:
      #   default            the platform- and printer-independent part: Klipper, Moonraker, Fluidd, KlipperScreen, network.
      #   raspberry-pi-2     the board: cross-compilation to armv7l, GPU-firmware boot, SPI TFT, CSI camera, power.
      #   ender3-v4-2-7      the printer: kinematics, pins, BL-Touch, bed mesh and macros of an Ender 3 with a 4.2.7 board.
      nixosModules = {
        default = { imports = [ ./modules ]; _module.args = { inherit sources fluidd-config; }; };
        raspberry-pi-2 = { imports = [ ./platforms/raspberry-pi-2 ]; _module.args = { inherit nixos-hardware; }; };
        ender3-v4-2-7 = ./printers/ender3-v4.2.7;

        # The three above together: an Ender 3 (4.2.7 board) on a Raspberry Pi 2 B. Add your user's SSH key (`nixosKlipper.admin`) and `system.stateVersion`.
        ender3-on-raspberry-pi-2 = {
          imports = [ self.nixosModules.default self.nixosModules.raspberry-pi-2 self.nixosModules.ender3-v4-2-7 ];
        };
      };

      # A complete machine, to check that the modules evaluate and to build the packages below. Yours goes in your own flake (see the README).
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        modules = [
          self.nixosModules.ender3-on-raspberry-pi-2
          {
            system.stateVersion = "26.05";
            nixosKlipper.admin.authorizedKeys = [ "ssh-ed25519 AAAA...replace-with-your-public-key" ];
          }
        ];
      };

      # Board MCU firmware (STM32F103), built with the same Klipper as the Pi. See packages/mcu-firmware.nix:
      #   nix build path:.#packages.aarch64-linux.mcu-firmware
      # Flashing the MCU from the Pi itself through the board's SD card (built for armv7l; see packages/sdcard-flasher.nix):
      #   nix build path:.#packages.aarch64-linux.sdcard-flasher
      packages.aarch64-linux.sdcard-flasher =
        self.nixosConfigurations.example.pkgs.callPackage ./packages/sdcard-flasher.nix {
          inherit klipper-src;
        };

      packages.aarch64-linux.mcu-firmware =
        nixpkgs.legacyPackages.aarch64-linux.callPackage ./packages/mcu-firmware.nix {
          inherit klipper-src;
          mcuConfig = ./printers/ender3-v4.2.7/ender3-v4.2.7.config;
        };
    };
}
