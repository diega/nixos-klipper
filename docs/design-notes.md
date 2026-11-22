# Design notes

## What is trimmed and why

### On any board (`modules/`)

- **Network: Ethernet with systemd-networkd, Wi-Fi with NetworkManager.** NetworkManager only manages `wlan0` (it is what the KlipperScreen network panel talks to; no VPN plugins or ModemManager, and NO Wi-Fi power saving). `eth0` goes through networkd, **without a fixed IP** (a fixed IP would only work with a peer that uses that same network): DHCP if there is a router, IPv4 link-local (169.254.x.x) as a fallback when there is no DHCP, and IPv6 link-local derived from the MAC (`fe80::` plus the EUI-64 of the MAC, does not change). It works for any machine plugged in by cable. **Why:** NetworkManager's wired connection, on a direct cable with no DHCP or IPv6 announcements, gives `ip-config-unavailable` after 45 s, removes ALL the addresses from eth0 and waits 5 minutes before retrying (~45 s reachable and 5 min unreachable); networkd has no "activation failure". Also: `usbcore.autosuspend=-1` and the sleep/suspend/hibernate targets disabled.
- **Trimmed firmware** for the USB Wi-Fi boards whose drivers are in the kernel (not all of linux-firmware). It covers Realtek (`rtlwifi` in full, including the RTL8188EUS and the RTL8192CU, and `rtw88`), Ralink (`rt2870`, `rt73`), MediaTek `mt7601u` and Atheros `ath9k_htc`. `mt76x0u/x2u/mt7921u` are NOT included (the copy fails) nor `carl9170`/`ar5523` (absent from linux-firmware): for a dongle that needs one of those, add its firmware in `modules/minimal.nix`.
- **Moonraker without pycurl and KlipperScreen without dbus-python:** nothing imports them, so they are left out whatever the architecture (nixpkgs' Moonraker lists pycurl although it no longer uses it, and it is one of the packages that do not cross-compile).
- **Prebuilt Fluidd 1.38.1** (official release) instead of building it with npm, which is slow and memory hungry; Fluidd is a static web app.
- **No `hardware.graphics` and no desktop:** `services.graphical-desktop` and `lightdm` are off (they pull in pipewire/ffmpeg, mesa/llvm). X only serves KlipperScreen over fbdev.

### Only on armv7l (`modules/armv7l.nix`)

Applied automatically when `nixpkgs.hostPlatform` is armv7l; a 64-bit board gets the packages as nixpkgs defines them. They exist because these packages do not build for that architecture, or do not cross-compile to it.

- **Klipper without numpy/matplotlib** (numpy drags in openblas, which does not build for armv7l). They are only needed with an accelerometer to calibrate the input shaper; `klipper-calibrate-shaper` warns that it is not available.
- **KlipperScreen without the camera panel.** `mpv` is removed (it drags in `yt-dlp` -> `deno`, which does not exist for armv7l, and `ffmpeg`). The **network** panel IS kept: it uses `sdbus-networkmanager`, and `sdbus` is patched to cross-compile (its `setup.py` calls `pkg-config` without a prefix). If the camera panel is opened, it fails; the rest works. The KlipperScreen `PYTHONPATH` is also reassembled (when cross-compiling, nixpkgs' recipe pulls in the builder's Python and the build fails).

### Raspberry Pi 2 B (`platforms/raspberry-pi-2/`)

- **Raspberry Pi kernel** (nixos-hardware) with the Pi 5 RP1 drivers turned off (`PWM_RP1`, `I2C_DESIGNWARE_*`, `VIDEO_RP1_CFE*`): they do not build in 32 bits. It is applied through `argsOverride`, not `boot.kernelPatches`. The `.config` has the hardware drivers: `FB_TFT_ILI9486`, `TOUCHSCREEN_ADS7846`, `RTL8XXXU`, `RTL8192CU`, `USB_SERIAL_CH341`, `USB_NET_SMSC95XX`, `MMC_BCM2835`, `KEYBOARD_GPIO`, fbcon rotation.
- **`system.boot.loader.kernelFile`:** the cross `zinstall` of that kernel leaves `vmlinuz-<version>` and not `zImage`; on the FAT it is copied as `zImage` anyway.
- **Minimal initrd:** only `mmc_block` (`CONFIG_MMC_BLOCK=m`); the ext4 root and MMC_BCM2835 are built in.
- **Camera:** CSI camera through the GPU's stack (`start_x=1`) and µStreamer (`platforms/raspberry-pi-2/camera.nix`); not libcamera/camera-streamer, which is not in nixos-26.05. Without a camera plugged in, the service does not start.

## Reference setup (what runs today)

- Klipper 0.14.0 in `ready` state, connected to the MCU (firmware built by `packages/mcu-firmware.nix`).
- Moonraker 0.11.0; Fluidd reads `printer.cfg`/`fluidd.cfg`.
- KlipperScreen 0.4.7 on the TFT (`/dev/fb1`), touch calibrated (`ADS7846`), connected to Moonraker. The network panel lists the networks. Settings changed from the screen (language, brightness...) persist.
- Ethernet via networkd; `avahi` and `nginx` active; `systemctl is-system-running` = `running`.
- The `klipperscreen` user has all the NetworkManager permissions that the network panel uses.
- The framebuffer capture comes out inverted, as expected with `Rotate UD` + `piscreen rotate=270`.
- Wi-Fi: USB dongle with an in-kernel driver, WPA2-PSK. The RTL8188EUS dongle has 1 antenna and 2.4 GHz: high latency (~100-300 ms), not suitable to rely on when a cable is available.
- Not tested: joining a NEW password-protected network from the panel (listing works).

## Where things are

| Part | File |
|---|---|
| `printer.cfg` | `printers/ender3-v4.2.7/printer.nix` |
| Fluidd macros (`[include fluidd.cfg]`, fluidd-config v1.2.1) | input `fluidd-config` + symlink in `modules/klipper.nix` |
| Moonraker, nginx/Fluidd | `modules/moonraker.nix` (without `update_manager`) |
| TFT + touch | `platforms/raspberry-pi-2/boot.nix` (`dtoverlay=piscreen`), `display.nix` (`fbcon=map:1 fbcon=rotate:2`, X fbdev and libinput matrix); `modules/klipperscreen.nix` runs KlipperScreen on top |
| Power button | `platforms/raspberry-pi-2/boot.nix` (`dtoverlay=gpio-shutdown`) |
| Network | `modules/network.nix` |
| Workarounds for 32-bit ARM | `modules/armv7l.nix` (applied only when the system is armv7l) |
| Camera | `platforms/raspberry-pi-2/camera.nix` |
| Board MCU | CH340 `/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0`; firmware in `packages/mcu-firmware.nix` |
