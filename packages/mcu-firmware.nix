{ stdenv, gcc-arm-embedded, python3, gnumake, klipper-src, mcuConfig }:

# Microcontroller firmware of the Ender 3 (board 4.2.7, STM32F103) built with the SAME Klipper that runs on the Pi (flake input `klipper-src`) and with the firmware configuration already installed (printers/ender3-v4.2.7/ender3-v4.2.7.config):
#   STM32F103, 28 KiB bootloader (0x8007000), 8 MHz crystal, serial on USART1 (PA10/PA9), 250000 baud.
# If any of that does not match the board, Creality's bootloader will not start the firmware, so do not touch those options without knowing why.
#
#   nix build path:.#packages.aarch64-linux.mcu-firmware
stdenv.mkDerivation {
  pname = "klipper-mcu-firmware-ender3";
  version = "0.14.0";
  src = klipper-src;

  nativeBuildInputs = [ gcc-arm-embedded python3 gnumake ];
  dontConfigure = true;
  dontFixup = true;

  postPatch = ''
    patchShebangs scripts
  '';

  buildPhase = ''
    runHook preBuild
    # Without a git repository, Klipper reads the version from klippy/.version (scripts/buildcommands.py).
    echo "v0.14.0-NixOS" > klippy/.version
    cp ${mcuConfig} .config
    chmod u+w .config
    make olddefconfig
    make -j$NIX_BUILD_CORES
    size out/klipper.elf
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp out/klipper.bin out/klipper.elf out/klipper.dict $out/
    # The .config actually used by the build (olddefconfig adds new 0.14.0 options).
    cp .config $out/used.config
    runHook postInstall
  '';
}
