# Power and operating notes

## Power consumption

All in software, in `platforms/raspberry-pi-2/power.nix` and `modules/network.nix`:

- **Bluetooth: not applicable.** The Pi 2 B has no Bluetooth hardware; on NixOS there is no service for it.
- **HDMI off** at boot (`tvservice -o`); set `nixosKlipper.power.hdmiOff = false` to debug with a monitor.
- **Wi-Fi power saving: disabled** on purpose (the priority is that the network does not drop).
- **CPU:** the kernel's default governor (`schedutil`, 600-900 MHz). `performance` (fixed 900 MHz) is not used: it does not measurably help the screen and it draws more power. Option `nixosKlipper.power.cpuGovernor` (default `null`).
- **LEDs: untouched** (they are used as a heartbeat). The green LED follows SD card activity; a fixed heartbeat would be `dtparam=act_led_trigger=heartbeat` via `nixosKlipper.boot.extraConfigTxt`.
- No `packagekit`, `udisks`, `triggerhappy` or desktop.

## Operating notes

**Printer macros** (defined in `modules/macros.nix`, enabled and tuned in `printers/ender3-v4.2.7/default.nix`):
- `MESH_MEASURE` measures the bed mesh hot (50 C, 3 min soak). `MESH_MEASURE SAVE=1` also saves it as profile `hot` (do it with an empty, clean bed). The macro has an `M400` before `SAVE_CONFIG` on purpose: without it Klipper re-reads its config (~0.3 s on this Pi) with the Z move still unsent and the MCU shuts down with `Timer too close` (recover with `FIRMWARE_RESTART`).
- `SDCARD_PRINT_FILE` is wrapped (`rename_existing`) so EVERY print loads the saved mesh automatically (`MESH_LOAD`); no slicer start G-code needed.
- `LOAD_FILAMENT` / `UNLOAD_FILAMENT` are what KlipperScreen's Filament buttons call; they heat the nozzle themselves (PLA, 200 C, 24 cm Bowden). Refused while printing.
- `LOAD_FILAMENT` and `UNLOAD_FILAMENT` split their long extruder moves into pieces of at most `nixosKlipper.macros.filament.maxMoveMm` (90 mm here), because Klipper refuses a single move longer than `max_extrude_only_distance` (100 mm).
- Restarting Klipper (a deploy that changes `printer.cfg` does it) while a heater is on leaves the board in `shutdown` (it protects itself when the host stops talking); recover with `FIRMWARE_RESTART`. Turn the heaters off before deploying.
- Bed mesh limits and `safe_z_home z_hop` account for the glass clips (they enter 12 mm over the glass); see the comments next to `bed_mesh`. The probe is 45 mm left and 3 mm in front of the nozzle, `z_offset` 3.92.

**Not enabled on purpose (cost in cross-compilation derivations):** rebuilding the kernel, classic D-Bus (needs a musl-compiled setuid wrapper), `iw`. Cheaper equivalents are used instead: `boot.kernelParams` (`initcall_blacklist=scx_init`, `kfence.sample_interval=0`), and an `environment.extraSetup` that removes the 4 duplicated D-Bus service files from system-path. If any of them is wanted, expect hours of toolchain builds.

**Builder gotchas:** the text of a derivation is part of it: editing a shell script, a patch or an `echo` inside a Nix string (firmware, ustreamer, klipper, KlipperScreen) rebuilds everything that depends on it, down to the armv7l toolchain. Comments outside strings are free. nix-darwin's weekly `nix-collect-garbage` (Sundays 03:15) deletes build-only paths (the armv7l toolchain, `-static` outputs) that no GC root keeps, so the next build suddenly wants to compile hundreds of derivations. Fix: import the running system's closure from the Pi (`nix copy --from ssh-ng://<host> --no-check-sigs <current-system>`), and build with `-o <link>` to keep a root. The builder VM has 8 GiB and runs up to 4 jobs of 6 cores: heavy builds get OOM-killed (`Killed signal terminated program cc1plus`); limit it with `--builders '<line from /etc/nix/machines with the job count set to 1>'`.
