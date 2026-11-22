{ config, lib, pkgs, ... }:

# Power reduction, all by software/configuration. What there is and what there isn't:
#
# - Bluetooth: the Pi 2 B does NOT have Bluetooth (it arrived with the Pi 3), so there is nothing to turn off. On NixOS no Bluetooth service is enabled; in the kernel `BT` is a module and would only load if a USB adapter were plugged in.
# - Wi-Fi: power saving DISABLED on purpose (modules/network.nix, wifi.powersave): the priority is that the network does not drop.
# - CPU: the kernel's default governor is kept, `schedutil` (varies between 600 and 900 MHz). Fixing it to `performance` (fixed 900 MHz) is not used: it does not measurably help (the bottleneck is the TFT's SPI bus, not the CPU) and it draws more power. See `nixosKlipper.power.cpuGovernor`, which stays as an option (null = the kernel's).
# - No desktop services (pipewire, udisks, packagekit, bluetooth...): less CPU at rest.
#
# The board's LEDs are NOT touched on purpose: they are used as a heartbeat to show the Pi is alive. (If a heartbeat independent of SD activity is ever wanted, it is `dtparam=act_led_trigger=heartbeat` in config.txt via nixosKlipper.boot.extraConfigTxt.)
let
  cfg = config.nixosKlipper.power;
in
{
  options.nixosKlipper.power = {
    hdmiOff = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Turn off the HDMI output at boot (`tvservice -o`). The console goes to the TFT (fbcon=map:1),
        so HDMI is not used. To debug with a monitor: set it to false.
      '';
    };
  };

  options.nixosKlipper.power.cpuGovernor = lib.mkOption {
    type = lib.types.nullOr (lib.types.enum [ "performance" "schedutil" "ondemand" "conservative" "powersave" ]);
    default = null;
    description = ''
      CPU frequency governor. `null` (default) keeps the kernel's (`schedutil`).
      `performance` keeps the fixed 900 MHz: not justified (see the comment above). The Pi 2 has a
      single frequency policy for its 4 cores, so writing to cpu0 is enough. It is done with a service that writes
      to sysfs rather than with `powerManagement.cpuFreqGovernor`, which drags in `cpupower` built against the
      Raspberry Pi kernel (cross to armv7l).
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.cpuGovernor != null) {
      # A service and not a tmpfiles rule: tmpfiles runs VERY early in boot, before the frequency module creates the governor file; the rule would fail silently and `schedutil` would come back after a reboot. The service waits for the file to appear.
      systemd.services.cpu-governor = {
        description = "Set the CPU governor (${cfg.cpuGovernor})";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          f=/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
          for _ in $(seq 60); do
            [ -w "$f" ] && break
            sleep 1
          done
          echo ${cfg.cpuGovernor} > "$f"
        '';
      };
    })
    (lib.mkIf cfg.hdmiOff {
      systemd.services.hdmi-off = {
        description = "Turn off the HDMI output (no monitor)";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.libraspberrypi}/bin/tvservice -o";
        };
      };
    })
  ];
}
