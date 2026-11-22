# Building, flashing and updating

## Building the image

Nix builds the image for the Pi's architecture (armv7l for the Pi 2 B). Any machine that can do that works: an aarch64 Linux machine (natively or with cross-compilation), an x86_64 Linux machine with emulation, or a remote builder. There is no binary cache for armv7l (cache.nixos.org only has x86_64, aarch64 and darwin), so the first build compiles hundreds of derivations; later builds reuse the builder's store. The image is ~590 MB compressed (2.6 GB uncompressed; the system expands to fill the whole SD on the first boot).

On macOS, the linux-builder of nix-darwin does it:

```sh
sudo launchctl kickstart system/org.nixos.linux-builder   # starts it (it is off by default)
nc -z localhost 31022                                      # checks that it is listening
nix build .#packages.aarch64-linux.sd-image                # in your machine's flake; takes long the first time
```

The builder's disk is 40 GB: if it fills up, run `nix store gc` inside the builder.

## Flashing and first boot

1. Write `result/sd-image/*.img.zst` to the SD card (`zstd -d` and `dd`).
2. Log in over SSH via the link-local IPv6, which is fixed (derived from the MAC) and works with any direct cable: `ssh <user>@'fe80::<EUI-64 of the MAC>%<interface>'` (the interface is your computer's, the one on that cable). Use the link IP, not `klipper.local` (mDNS stops resolving when the Pi does not respond). With a router, the Pi gets an address via DHCP.
3. Wi-Fi: the network is managed by NetworkManager. From the touchscreen, use the **Network** panel of KlipperScreen, or over SSH: `nmcli device wifi connect "SSID" password "PASSWORD"`. Connections are stored in `/etc/NetworkManager/system-connections` and survive rebuilds; there are no passwords in the repo.

## Updating

```sh
nix run nixpkgs#nixos-rebuild-ng -- switch --flake .#<host> --target-host <host> --sudo
```

Use `klipper.local` (or an SSH alias that points at it) as the target host, so that it keeps working when the router hands out a different IP. The fe80:: address of the section above only works with the direct cable plugged in. The armv7l build is done by the local linux-builder (nix-darwin). After a switch, check it with `readlink /run/current-system /nix/var/nix/profiles/system` (identical) and `systemctl --failed`. Run `dry-activate` instead of `switch` to preview.

`boot.loader.external` (platforms/raspberry-pi-2/boot.nix) copies kernel, initrd, dtbs, overlays, `config.txt` and `cmdline.txt` to the FAT partition on every switch. Changes to `boot.kernelParams` take effect after a reboot and need `--install-bootloader`. Rollback: `nixos-rebuild switch --rollback`.

## Persistent data

Everything mutable lives under `/var/lib`: `moonraker/` (gcodes, database with the job history and the `fluidd`/`mobileraker` namespaces), `klipper/` (the `SAVE_CONFIG` block of `printer.cfg`, logs), `klipperscreen/` (the settings changed from the screen). `printer.cfg` itself is `modules/printer.nix`. To copy gcodes and the Moonraker database to another machine:

```sh
sudo systemctl stop moonraker
sudo rsync -a --chown=moonraker:moonraker SRC/gcodes/   /var/lib/moonraker/gcodes/
sudo rsync -a --chown=moonraker:moonraker SRC/database/ /var/lib/moonraker/database/
sudo systemctl start moonraker
```
