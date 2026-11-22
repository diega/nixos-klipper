{ stdenv, python3, makeWrapper, klipper, klipper-src }:

# Klipper tool to flash the MCU through the board's SD card FROM the Pi, without removing the SD (scripts/flash-sdcard.sh in the Klipper repo; the 4.2.7 is supported as `creality-v4.2.7`).
#
# Why a package: the tool compiles `fatfs.so` with gcc the first time it runs, and NixOS on the Pi has no compiler. Here it is precompiled for armv7l (on the builder) and a tree is assembled with the same structure it expects (scripts/spi_flash, lib/fatfs, klippy with its already-compiled c_helper.so, taken from the `klipper` package that already runs on the Pi). The store timestamps are all equal, so chelper's `check_build_code` does not try to recompile anything.
#
#   klipper-flash-sdcard [-d klipper.dict] <device> creality-v4.2.7 klipper.bin
let
  py = python3.withPackages (p: with p; [ python-can cffi pyserial greenlet jinja2 markupsafe msgspec ]);
in
stdenv.mkDerivation {
  pname = "klipper-sdcard-flasher";
  version = "0.14.0";
  src = klipper-src;

  nativeBuildInputs = [ makeWrapper ];
  dontConfigure = true;
  dontFixup = true;

  buildPhase = ''
    runHook preBuild
    # Same sources and options as fatfs_lib.py (no LTO or SSE: they do not apply to ARM).
    $CC -Wall -O2 -shared -fPIC -o scripts/spi_flash/fatfs.so \
      lib/fatfs/ff.c lib/fatfs/ffsystem.c lib/fatfs/ffunicode.c scripts/spi_flash/fatfs_api.c
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    k=$out/klipper
    mkdir -p $k/scripts $k/lib $out/bin
    cp -r klippy $k/klippy
    cp -r scripts/spi_flash $k/scripts/spi_flash
    cp -r lib/fatfs $k/lib/fatfs
    chmod -R u+w $k
    cp ${klipper}/lib/klipper/chelper/c_helper.so $k/klippy/chelper/c_helper.so
    makeWrapper ${py}/bin/python $out/bin/klipper-flash-sdcard --add-flags $k/scripts/spi_flash/spi_flash.py
    runHook postInstall
  '';
}
