{
  # nixos-klipper: the platform- and printer-independent part (Klipper, Moonraker, Fluidd, KlipperScreen, network).
  imports = [
    ./options.nix
    ./system.nix
    ./minimal.nix
    ./network.nix
    ./klipper.nix
    ./moonraker.nix
    ./klipperscreen.nix
    ./macros.nix
    ./armv7l.nix
  ];
}
