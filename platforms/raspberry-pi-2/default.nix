{
  # Raspberry Pi 2 B (armv7l): cross-compilation, GPU-firmware boot, SPI TFT, CSI camera and power settings.
  imports = [
    ./options.nix
    ./platform.nix
    ./system.nix
    ./boot.nix
    ./display.nix
    ./camera.nix
    ./power.nix
  ];
}
