{
  # Creality Ender 3 with the 4.2.7 board (STM32F103) and a BL-Touch.
  imports = [ ./printer.nix ];

  # Bed mesh measured hot and loaded by every print; Load / Unload filament buttons for PLA at 200 °C.
  # 24 cm Bowden tube between the extruder and the hotend (measured by the owner): 230 mm are pushed fast and 50 mm slow to purge.
  nixosKlipper.macros = {
    enable = true;
    filament.loadMm = 230;
    filament.unloadMm = 270;
    # Moves of 90 mm: the unload (3 x 90 mm) has been run on this printer; Klipper's limit per move is 100 mm in `extruder`.
    filament.maxMoveMm = 90;
  };
}
