{ config, lib, pkgs, nixos-hardware, ... }:

# Raspberry Pi 2 Model B (BCM2836, armv7l, 1 GB).
# Apple Silicon cannot run 32-bit ARM binaries, so everything is cross-compiled on the linux-builder (aarch64-linux) of nix-darwin.
{
  nixpkgs.buildPlatform = "aarch64-linux";
  nixpkgs.hostPlatform = lib.systems.examples.armv7l-hf-multiplatform;

  # Raspberry Pi kernel (it has fbtft/ili9486, ads7846 and the `piscreen` and `gpio-shutdown` overlays that the printer needs).
  #
  # nixos-hardware only turns off the Pi 5 (RP1) drivers for the Pi 1; on the Pi 2 the modpost also fails (__aeabi_uldivmod/ldivmod in 32-bit modules). Same problem: https://github.com/NixOS/nixpkgs/issues/464515 `boot.kernelPatches` does not work here (NixOS only applies it to nixpkgs' standard kernels); the recipe's hook is `argsOverride`, which REPLACES structuredExtraConfig entirely. So what nixos-hardware (kernel.nix, rpiVersion = 2) already sets is repeated here, plus the RP1 drivers turned off. Boot parameters instead of rebuilding the kernel (zero compile derivations; they apply from the next reboot, with --install-bootloader):
  #  - initcall_blacklist=scx_init: sched_ext (BPF schedulers) is not used and on this kernel it logs `sched_ext: Failed to register kfunc sets (-22)` (ERROR level) on every boot.
  #  - kfence.sample_interval=0: turns KFENCE (a memory debugging detector) off. It reports on every boot `BUG: KFENCE: memory corruption in hub_port_init` (2 bytes written past the end of a buffer during USB hub initialization, known in the Pi's dwc_otg controller). Turned off to keep the boot log free of errors, at the cost of losing that detection.
  boot.kernelParams = [ "initcall_blacklist=scx_init" "kfence.sample_interval=0" ];

  boot.kernelPackages =
    let
      inherit (lib.kernel) freeform yes no;
      cc = config.nixosKlipper.build.ccache;
      # Same wrapper as `programs.ccache.packageNames` in NixOS, but here: that module acts on the nixpkgs of the machine that EVALUATES, and we evaluate on the Mac, not on the builder. Without the ccache tests: on the builder (aarch64) one of them (`debug_prefix_map`) calls the cross armv7l objdump on a native object and fails, and the kernel never gets to compile.
      ccacheNoCheck = pkgs.extend (final: prev: { ccache = prev.ccache.overrideAttrs (_: { doCheck = false; }); });
      ccacheStdenv = ccacheNoCheck.ccacheStdenv.override {
        extraConfig = ''
          export CCACHE_COMPRESS=1
          export CCACHE_SLOPPINESS=random_seed
          export CCACHE_DIR="${cc.dir}"
          export CCACHE_UMASK=007
          if [ ! -d "$CCACHE_DIR" ] || [ ! -w "$CCACHE_DIR" ]; then
            echo "=====" >&2
            echo "ccache: '$CCACHE_DIR' does not exist or is not writable on this builder." >&2
            echo "Programs.ccache must be enabled in the builder VM (nix-darwin-macross)," >&2
            echo "or nixosKlipper.build.ccache.enable turned off." >&2
            echo "=====" >&2
            exit 1
          fi
        '';
      };
    in
    pkgs.linuxPackagesFor (
      pkgs.callPackage "${nixos-hardware}/raspberry-pi/common/kernel.nix" ({
        rpiVersion = 2;
        argsOverride.structuredExtraConfig = {
          # --- same as nixos-hardware for the Pi 2
          NR_CPUS = lib.mkForce (freeform "4");
          CMA_SIZE_MBYTES = lib.mkForce (freeform "5");
          NFS_FS = lib.mkForce yes;
          NFS_V4 = yes;
          ROOT_NFS = yes;
          IP_PNP = lib.mkForce yes;
          IP_PNP_DHCP = yes;
          IP_PNP_RARP = yes;
          NET_CLS_BPF = lib.mkForce yes;
          NLS_CODEPAGE_437 = lib.mkForce yes;
          FB_SIMPLE = yes;
          PREEMPT = lib.mkForce no;
          PREEMPT_LAZY = lib.mkForce no;
          PREEMPT_VOLUNTARY = lib.mkForce yes;
          # (SCHED_CLASS_EXT = lib.mkForce no is not used: rebuilding the kernel means building the whole armv7l toolchain on the builder. The same effect without compiling is obtained with boot.kernelParams, below.) --- added: Pi 5 drivers that do not build in 32 bits
          PWM_RP1 = no;
          I2C_DESIGNWARE_CORE = no;
          I2C_DESIGNWARE_SLAVE = no;
          I2C_DESIGNWARE_PLATFORM = no;
          I2C_DESIGNWARE_PCI = no;
          VIDEO_RP1_CFE = no;
          VIDEO_RP1_CFE_DOWNSTREAM = no;
        };
      } // lib.optionalAttrs cc.enable { stdenv = ccacheStdenv; })
    );

  # When cross-compiling, the `make zinstall` of the Raspberry Pi kernel leaves `vmlinuz-<version>` and not the `zImage` that NixOS expects (nixpkgs' `installkernel` trick does not apply with that tree). NixOS checks this name when assembling the system; boot.nix copies it to the FAT as `zImage`.
  system.boot.loader.kernelFile =
    lib.mkForce "vmlinuz-${config.boot.kernelPackages.kernel.modDirVersion}";

  # GPU firmware and Wi-Fi dongle blobs: they are not free software.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "raspberrypi-firmware" "linux-firmware" ];
}
