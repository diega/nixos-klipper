# nixos-klipper

Declarative NixOS modules for running a 3D printer with Klipper. Describe the printer, the board and your own choices in a few lines of Nix, and get a complete system: Klipper, Moonraker, Fluidd (web interface), KlipperScreen on a small SPI touchscreen, Wi-Fi, mDNS (`klipper.local`), and a ready-to-flash SD image.

## What you get

- **The whole printer as code.** `printer.cfg` is generated from Nix, together with the system around it, so a printer can be rebuilt from scratch, reviewed in a diff, or copied to a second machine.
- **Pinned, reproducible versions.** Klipper, Moonraker, KlipperScreen and Fluidd are pinned by `flake.lock`; an update is a deliberate change, not a surprise.
- **Atomic updates and rollback.** `nixos-rebuild switch` swaps the system in one step and `--rollback` returns to the previous one, including the kernel and the boot files.
- **A touchscreen that works out of the box.** KlipperScreen on an SPI TFT with the touch calibrated, its network panel backed by NetworkManager, and the settings changed on the screen kept across reboots and updates.
- **Print helpers for people who just want to print.** A bed mesh measured once and loaded by every print, and Load / Unload filament buttons that heat the nozzle themselves.
- **Board and printer are separate modules.** What is specific to a Raspberry Pi or to an Ender 3 lives in its own directory, so another board or printer is another directory, not a fork.
- **Your choices stay yours.** Your user, SSH key, time zone and Wi-Fi region live in your own flake; this repository holds no personal data.
- **The printer's microcontroller firmware too.** It is built from the same Klipper version as the host and flashed through the board's SD card.

Included today: a Raspberry Pi 2 B as the board and a Creality Ender 3 with a 4.2.7 board as the printer.

## Quick start

Put your own choices in your own flake that uses this one as an input. Nothing else is needed:

```nix
{
  inputs.nixos-klipper.url = "github:diega/nixos-klipper";
  inputs.nixpkgs.follows = "nixos-klipper/nixpkgs";

  outputs = { self, nixpkgs, nixos-klipper, ... }: {
    nixosConfigurations.printer = nixpkgs.lib.nixosSystem {
      modules = [
        nixos-klipper.nixosModules.ender3-on-raspberry-pi-2
        {
          system.stateVersion = "26.05";
          networking.hostName = "klipper";   # also the mDNS name: klipper.local
          time.timeZone = "Europe/Madrid";
          nixosKlipper = {
            admin = { name = "me"; authorizedKeys = [ "ssh-ed25519 AAAA... me@laptop" ]; };
            regulatoryDomain = "ES";          # your country's Wi-Fi region
            camera.enable = false;            # true with a CSI camera
          };
        }
      ];
    };
    packages.aarch64-linux.sd-image = self.nixosConfigurations.printer.config.system.build.sdImage;
  };
}
```

The options are `nixosKlipper.admin.*` (the SSH-key-only administrator account), `nixosKlipper.regulatoryDomain`, `nixosKlipper.camera.enable` and `nixosKlipper.macros.*` (see `modules/macros.nix`). Anything else is ordinary NixOS configuration.

## Structure

The repository is split in layers, so that what is specific to one printer or one board is isolated:

| Layer | Where | Exported as | What it holds |
|---|---|---|---|
| Generic | `modules/` | `nixosModules.default` | Klipper, Moonraker, Fluidd (nginx), KlipperScreen with its patches, network (NetworkManager for Wi-Fi, networkd for Ethernet), minimal image, SSH, time sync, and the print-helper macros (`macros.nix`: bed mesh loaded by every print, Load / Unload filament; tuned with `nixosKlipper.macros.*`), plus `armv7l.nix`, the workarounds that apply only on 32-bit ARM |
| Board | `platforms/raspberry-pi-2/` | `nixosModules.raspberry-pi-2` | armv7l cross-compilation and kernel, GPU-firmware boot (`boot.nix`), SPI TFT, X driver and touch matrix (`display.nix`), CSI camera (`camera.nix`), power (`power.nix`), swap, watchdog and the SoC temperature sensor |
| Printer | `printers/ender3-v4.2.7/` | `nixosModules.ender3-v4-2-7` | `printer.cfg` (steppers, pins, BLTouch, bed mesh), the values for the macros (nozzle temperature, tube length) and the MCU firmware configuration |

`packages/` has the MCU firmware build (`mcu-firmware.nix`, which takes the printer's configuration) and the tool to flash it through the board's SD card (`sdcard-flasher.nix`). Options live under `nixosKlipper.*`.

To build a machine, import `nixosModules.ender3-on-raspberry-pi-2` (the three modules together) from your own flake and add your own choices; see "Quick start". A new printer is a new directory under `printers/` with its own `printer.cfg` settings and firmware configuration; a new board is a new directory under `platforms/`.

## Documentation

- [Building, flashing and updating](docs/building-and-deploying.md): build the SD image (including from macOS), first boot, updates, rollback and where the data lives.
- [MCU firmware](docs/mcu-firmware.md): build the printer board's firmware and flash it through its SD card.
- [Operations](docs/operations.md): the print-helper macros, power settings and build-host notes.
- [Design notes](docs/design-notes.md): what is trimmed from the image and why, the reference setup and where each part lives.

## License

Copyright (C) 2026 Diego López León

This repository is free software, licensed under the GNU General Public License version 3 or (at your option) any later version (`GPL-3.0-or-later`). The full text is in `LICENSE`. It is the same license as Klipper, Moonraker and Fluidd, which the Nix code builds and configures as separate programs.

One file is under a different license: `patches/klipperscreen-0.4.7-robust-network-list.patch` modifies KlipperScreen, which is licensed under the GNU Affero General Public License version 3 (`LICENSES/AGPL-3.0.txt`), so the patch keeps that license. Both licenses allow combining works under them (section 13 of each).
