{ config, lib, pkgs, modulesPath, ... }:

# Direct boot through the GPU firmware, without U-Boot (config.txt + cmdline.txt + dtbs + overlays on the FAT partition), so `dtoverlay=piscreen` in config.txt works as documented.
#
# - The SD image is built with `installText` on the firmware partition.
# - `nixos-rebuild switch/boot` runs the same text via `boot.loader.external` so that the FAT always points to the active generation (there is no generation menu: rollback is `nixos-rebuild switch --rollback`).
let
  fw = "${pkgs.raspberrypifw}/share/raspberrypi/boot";

  # GPU firmware configuration.
  configTxt = pkgs.writeText "config.txt" ''
    kernel=zImage
    initramfs initrd followkernel
    disable_splash=1
    boot_delay=0
    disable_overscan=1
    ${config.nixosKlipper.boot.extraConfigTxt}
    # Power button on GPIO3
    dtoverlay=gpio-shutdown
    # TFT 3.5" ILI9486 + ADS7846 touch over SPI (ends up as /dev/fb1 and event1). speed=24000000 is the overlay's default. The Pi 2's SPI0 comes from a 250 MHz clock with an EVEN divider, so 24 MHz is 250/12 = 20.8 MHz real. DO NOT RAISE IT: with speed=32000000 (divider 8 -> 31.25 MHz) image quality is noticeably worse (the ILI9486 panel does not follow that clock). The possible dividers above are 10 (25 MHz) and 8 (31.25 MHz); 25 MHz is untested.
    dtoverlay=piscreen,speed=24000000
  '';

  installText = { top, dest }: ''
    kdir=$(dirname "$(readlink -f ${top}/kernel)")
    cp ${fw}/bootcode.bin ${fw}/fixup.dat ${fw}/start.elf ${dest}/
    ${lib.optionalString config.nixosKlipper.camera.enable "# Camera-capable firmware (start_x=1 in config.txt); the regular ones are kept too.\n    cp ${fw}/start_x.elf ${fw}/fixup_x.dat ${dest}/"}
    cp ${top}/kernel ${dest}/zImage
    cp ${top}/initrd ${dest}/initrd
    cp "$kdir/dtbs/bcm2709-rpi-2-b.dtb" ${dest}/
    mkdir -p ${dest}/overlays
    cp -r "$kdir/dtbs/overlays/." ${dest}/overlays/
    cp ${configTxt} ${dest}/config.txt
    # cmdline.txt last: it is what activates the new generation.
    echo "init=${top}/init $(cat ${top}/kernel-params)" > ${dest}/cmdline.txt.new
    mv ${dest}/cmdline.txt.new ${dest}/cmdline.txt
  '';

  installHook = pkgs.writeShellScript "install-rpi-boot-files" ''
    set -eu
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.util-linux ]}
    # Explicit device, not dependent on fstab: the hook runs BEFORE the new generation is activated, i.e. with the fstab of the running one (which may have another label/device).
    mountpoint -q /boot/firmware || mount -t vfat /dev/mmcblk0p1 /boot/firmware
    # `/boot/firmware` is in fstab with `nofail`: if the device is not found, `mount` returns SUCCESS without mounting anything, and the boot files would be copied to a plain directory at the root while the GPU firmware keeps reading the real FAT (the system would reboot into an old generation and config.txt changes would not apply). So the mount is required.
    mountpoint -q /boot/firmware || {
      echo "ERROR: the boot FAT partition is not mounted at /boot/firmware; nothing is copied." >&2
      exit 1
    }
    ${installText { top = "\"$1\""; dest = "/boot/firmware"; }}
    sync
  '';
in
{
  imports = [ "${modulesPath}/installer/sd-card/sd-image.nix" ];

  # The boot FAT is always partition 1 of the SD. It is NOT looked up by label: it is `FIRMWARE` on images built here and `bootfs` on Raspberry Pi OS ones, and with the wrong label the mount fails silently (see the hook below).
  fileSystems."/boot/firmware".device = lib.mkForce "/dev/mmcblk0p1";

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = false;
  boot.loader.external = {
    enable = true;
    installHook = "${installHook}";
  };

  sdImage = {
    firmwareSize = 128;
    populateFirmwareCommands = installText { top = "${config.system.build.toplevel}"; dest = "firmware"; };
    populateRootCommands = "";
  };

  # CLASSIC initrd (not systemd's, which is the default in 26.05). `/etc/NIXOS_LUSTRATE`, the documented way to replace an existing system in place (it moves everything old to /old-root on the next boot), is implemented only in the classic initrd (stage-1-init.sh); the systemd initrd does not have it.
  boot.initrd.systemd.enable = false;

  # Minimal initrd. NixOS's default list (3w-9xxx, ahci, nvme, virtio...) assumes a generic kernel with everything as modules; the Raspberry Pi one does not have them and modprobe aborts. To boot from the SD, mmc_block (CONFIG_MMC_BLOCK=m) is enough: the ext4 root, the MMC_BCM2835 controller and VFAT are built into the kernel.
  boot.initrd.includeDefaultModules = false;
  boot.initrd.availableKernelModules = lib.mkForce [ "mmc_block" ];
  boot.initrd.kernelModules = lib.mkForce [ ];

  # The generic image pulls in ZFS; it is not used here.
  boot.supportedFilesystems.zfs = lib.mkForce false;
}
