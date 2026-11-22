{ config, lib, pkgs, modulesPath, ... }:

# Mini image: no documentation or default packages, and only the firmware that is needed.
{
  imports = [ "${modulesPath}/profiles/minimal.nix" ];

  environment.defaultPackages = lib.mkForce [ ];
  boot.supportedFilesystems = lib.mkForce [ "ext4" "vfat" ];
  system.disableInstallerTools = true;

  # Instead of all of linux-firmware (hundreds of MB), only the firmware of the USB Wi-Fi boards whose drivers the kernel ships. What IS copied: Realtek (full rtlwifi, which includes the RTL8188EUS and RTL8192CU; rtw88), Ralink (rt2870, rt73), MediaTek mt7601u and Atheros ath9k_htc. What is NOT there: mt76x0u/x2u/mt7921u (the copy fails, see the WARNING lines in the build log) and carl9170/ar5523 (absent from this linux-firmware version). rtw89 (Wi-Fi 6, ~5 MB, rare on USB) is left out. `cp -L`: in linux-firmware several names are symlinks (e.g. mt7601u.bin -> mediatek/...); they are copied as real files so no broken links remain (NixOS aborts if there are any).
  hardware.enableRedistributableFirmware = lib.mkForce false;
  hardware.firmware = [
    (pkgs.runCommand "firmware-wifi-usb" { } ''
      src=${pkgs.linux-firmware}/lib/firmware
      mkdir -p $out/lib/firmware
      cd "$src"
      for p in \
        rtlwifi rtw88 \
        'rt2870.bin*' 'rt73.bin*' 'mt7601u.bin*' 'mediatek/mt7601u.bin*' \
        'mediatek/mt7610*' 'mediatek/mt7662*' 'mediatek/WIFI_*MT7961*' \
        ath9k_htc 'ar5523.bin*' 'carl9170-1.fw*'
      do
        # shellcheck disable=SC2086
        for f in $p; do
          if [ -e "$f" ]; then
            cp -rL --parents "$f" "$out/lib/firmware/" && echo "firmware: $f" || echo "WARNING: could not copy $f"
          fi
        done
      done
      # the RTL8188EUS firmware is the one that matters: fail the build if it is missing
      ls $out/lib/firmware/rtlwifi/rtl8188eufw.bin*
    '')
  ];

  # Fewer writes to the SD.
  boot.tmp.useTmpfs = true;
}
