# MCU firmware

`packages/mcu-firmware.nix` builds the board's firmware (STM32F103) with the SAME Klipper as the Pi (`klipper-src`, v0.14.0) and the configuration in `printers/ender3-v4.2.7/ender3-v4.2.7.config`:

```sh
nix build path:.#packages.aarch64-linux.mcu-firmware   # klipper.bin ends up in ./result
```

The configuration reproduces the board's hardware, option by option (MCU `stm32f103xe`, 72 MHz with an 8 MHz crystal, 28 KiB bootloader -> application at `0x8007000`, USART1 at 250000). It is a minimal recipe with the low-level options; `olddefconfig` fills in the rest (the generated config ends up in `result/used.config`). If any of those options does not match the board, Creality's bootloader will not start the firmware.

It is flashed **through the board's SD card**. There are two ways:

1. **From the Pi, without removing the SD** (the 4.2.7 is supported in `flash-sdcard.sh` as `creality-v4.2.7`: the MCU talks software SPI to the board's SD slot and writes the file). It requires a FAT32 microSD **inserted in the board's slot** (Creality recommends 4096-byte clusters). `packages/sdcard-flasher.nix` builds the tool already compiled for armv7l (the original compiles `fatfs.so` with gcc, which the Pi does not have) (the flashing tool DELETES the other `.bin` files in the root and names the file `<datetime>firmware.bin`, so use a card whose contents do not matter):

   ```sh
   nix build path:.#packages.aarch64-linux.sdcard-flasher
   nix copy --no-check-sigs --to ssh://<host> ./result
   # on the Pi (with Klipper stopped; restart it at the end):
   sudo systemctl stop klipper
   sudo ./result/bin/klipper-flash-sdcard -d klipper.dict /dev/serial/by-id/usb-1a86_USB_Serial-if00-port0 creality-v4.2.7 klipper.bin
   ```

   Creality's bootloader reads the SD in SDIO mode and the card is left in SPI mode, so after writing you have to **power the printer off and back on** (power cut to the board and the card) so the bootloader completes the flash. With an empty slot the tool fails before writing anything: `failed to reset SD Card ... Is it inserted?`.
2. **Moving the SD** by hand (copy `klipper.bin` under a new name, insert it, power on).
