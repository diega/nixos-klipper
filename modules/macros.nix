{ config, lib, ... }:

# Print-helper macros that work on any Klipper machine that has a probe-based [bed_mesh] and a Bowden or direct extruder: a bed mesh measured once and loaded by every print, and Load / Unload filament buttons that heat the nozzle themselves. The numbers that depend on the printer (temperatures, tube length) are options; the printer module sets them.
let
  cfg = config.nixosKlipper.macros;

  # The NixOS module writes multiline values as they are, and Klipper requires continuation lines to be indented (otherwise it reads them as new keys). This indents them.
  macro = body: "\n" + lib.concatMapStringsSep "\n" (l: if l == "" then "" else "  " + l)
    (lib.splitString "\n" (lib.removeSuffix "\n" body));

  # `G1 E<sign><mm> F<speed>` lines that add up to `total` mm, none longer than `maxMoveMm` (see the comment above LOAD_FILAMENT).
  moves = sign: speed: total:
    let
      n = total / cfg.filament.maxMoveMm;
      rest = total - n * cfg.filament.maxMoveMm;
      pieces = lib.genList (_: cfg.filament.maxMoveMm) n ++ lib.optional (rest > 0) rest;
    in
    lib.concatMapStringsSep "\n" (d: "G1 E${sign}${toString d} F${speed}") pieces;
in
{
  options.nixosKlipper.macros = {
    enable = lib.mkEnableOption "the bed-mesh and filament macros (MESH_MEASURE, MESH_LOAD, SDCARD_PRINT_FILE wrapper, LOAD_FILAMENT, UNLOAD_FILAMENT). Needs a [bed_mesh] section in the printer configuration";

    mesh = {
      bedTemp = lib.mkOption { type = lib.types.int; default = 50; description = "Bed temperature (°C) at which the mesh is measured by default."; };
      soakMinutes = lib.mkOption { type = lib.types.int; default = 3; description = "Minutes to wait for the bed to stabilize before measuring."; };
      profile = lib.mkOption { type = lib.types.str; default = "hot"; description = "Name of the saved mesh that every print loads."; };
    };

    filament = {
      name = lib.mkOption { type = lib.types.str; default = "PLA"; description = "Material the Load / Unload buttons are meant for (only used in the descriptions)."; };
      nozzleTemp = lib.mkOption { type = lib.types.int; default = 200; description = "Nozzle temperature (°C) while loading and unloading."; };
      loadMm = lib.mkOption { type = lib.types.int; default = 230; description = "Filament pushed fast when loading: about the length of the tube between the extruder and the hotend."; };
      purgeMm = lib.mkOption { type = lib.types.int; default = 50; description = "Filament pushed slowly after loading, to purge the old color."; };
      unloadMm = lib.mkOption { type = lib.types.int; default = 270; description = "Filament pulled back when unloading."; };
      maxMoveMm = lib.mkOption { type = lib.types.int; default = 80; description = "Longest single extruder move. It must be below `max_extrude_only_distance` of the [extruder] section (100 mm by default)."; };
    };
  };

  config = lib.mkIf cfg.enable {
    services.klipper.settings = {
      # MESH FLOW: measure once and reuse (measuring on every print would add several minutes).
      #
      #  1. With the bed EMPTY and clean:   MESH_MEASURE SAVE=1 Measures hot and saves the mesh as "hot" (SAVE_CONFIG: Klipper restarts). It is saved in the SAVE_CONFIG block of printer.cfg, which is kept across deployments.
      #  2. Every print loads the saved mesh by itself (see the SDCARD_PRINT_FILE wrapper below). MESH_LOAD does the same by hand (instant); if there is no saved mesh, it stops with a message.
      #  3. Repeat step 1 only when needed: after moving the bed screws, changing the glass or the surface, or if the first layer comes out uneven.
      #
      # The mesh is valid for the bed temperature it was measured at (default 50 °C, PLA). For another temperature it is saved under another name: MESH_MEASURE BED_TEMP=80 PROFILE=petg SAVE=1  and  MESH_LOAD PROFILE=petg.
      #
      # MESH_MEASURE parameters: BED_TEMP (°C, 50), SOAK_MIN (minutes of waiting, 3), KEEP_BED=1 (leaves the bed on, 0), PROFILE (name, "hot"), SAVE=1 (saves with SAVE_CONFIG, 0). The nozzle is not heated: the BL-Touch does not need it. Do not use SAVE=1 during a print: SAVE_CONFIG restarts Klipper. The M400 before SAVE_CONFIG is REQUIRED: it waits for the Z lift to finish. Without it, Klipper rereads the configuration (0.27 s on this Pi) with that move still unsent to the board, the first step arrives late (the margin is 250 ms) and the MCU shuts down with "Timer too close"; recover with FIRMWARE_RESTART. Same rule for any macro that moves something and then right away does heavy work: put an M400 in between.
      "gcode_macro MESH_MEASURE" = {
        description = "Measures the bed mesh with the bed hot (MESH_MEASURE SAVE=1 to save it)";
        gcode = macro ''
          {% set bed_temp = params.BED_TEMP|default(${toString cfg.mesh.bedTemp})|float %}
          {% set soak = params.SOAK_MIN|default(${toString cfg.mesh.soakMinutes})|float %}
          {% set keep = params.KEEP_BED|default(0)|int %}
          {% set profile = params.PROFILE|default('${cfg.mesh.profile}') %}
          {% set save = params.SAVE|default(0)|int %}
          M140 S{bed_temp}
          G28
          M190 S{bed_temp}
          {% if soak > 0 %}
            RESPOND MSG="MESH_MEASURE: waiting {soak} min for the bed to stabilize"
            G4 P{(soak * 60000)|int}
          {% endif %}
          BED_MESH_CALIBRATE PROFILE={profile}
          G1 Z10 F600
          M400
          {% if keep == 0 %}
            M140 S0
          {% endif %}
          {% if save == 1 %}
            RESPOND MSG="MESH_MEASURE: saving the {profile} mesh (Klipper restarts)"
            SAVE_CONFIG
          {% endif %}
        '';
      };

      "gcode_macro MESH_LOAD" = {
        description = "Loads the saved mesh (for the slicer's start G-code, after G28)";
        gcode = macro ''
          {% set profile = params.PROFILE|default('${cfg.mesh.profile}') %}
          {% if profile in printer.bed_mesh.profiles %}
            BED_MESH_PROFILE LOAD={profile}
          {% else %}
            {action_raise_error("There is no saved mesh named " ~ profile ~ ". Run MESH_MEASURE SAVE=1 with the bed empty.")}
          {% endif %}
        '';
      };

      # LOAD / UNLOAD FILAMENT. KlipperScreen's "Load" and "Unload" buttons (Filament) call exactly LOAD_FILAMENT and UNLOAD_FILAMENT (with SPEED, which is ignored here), without heating first: these macros heat up on their own, so whoever uses them only has to press the button. Always PLA at 200 °C. 24 cm Bowden tube between the extruder and the hotend (measured by the owner): 230 mm are pushed fast and 50 mm slow to purge the old color. At the end they turn the hotend off.
      # Klipper refuses any single extruder-only move longer than max_extrude_only_distance (100 mm, in `extruder`), so the long loading and unloading moves are split into pieces under that limit instead of raising it.
      "gcode_macro LOAD_FILAMENT" = {
        description = "Loads filament (${cfg.filament.name}): heats up, pushes it through the tube and purges";
        gcode = macro ''
          {% if printer.print_stats.state == "printing" %}
            {action_raise_error("Cannot load filament while printing.")}
          {% endif %}
          SAVE_GCODE_STATE NAME=load_filament
          RESPOND MSG="Loading filament: heating the nozzle to ${toString cfg.filament.nozzleTemp} °C..."
          M109 S${toString cfg.filament.nozzleTemp}
          M83
          ${moves "" "600" cfg.filament.loadMm}
          RESPOND MSG="Purging: plastic should come out of the nozzle."
          G1 E${toString cfg.filament.purgeMm} F150
          M104 S0
          RESTORE_GCODE_STATE NAME=load_filament
          RESPOND MSG="Done. If the plastic came out the right color, you can print now."
        '';
      };

      "gcode_macro UNLOAD_FILAMENT" = {
        description = "Unloads filament (${cfg.filament.name}): heats up and pulls it out through the tube";
        gcode = macro ''
          {% if printer.print_stats.state == "printing" %}
            {action_raise_error("Cannot unload filament while printing.")}
          {% endif %}
          SAVE_GCODE_STATE NAME=unload_filament
          RESPOND MSG="Unloading filament: heating the nozzle to ${toString cfg.filament.nozzleTemp} °C..."
          M109 S${toString cfg.filament.nozzleTemp}
          M83
          G1 E10 F150
          ${moves "-" "900" cfg.filament.unloadMm}
          M104 S0
          RESTORE_GCODE_STATE NAME=unload_filament
          RESPOND MSG="Done. Pull out the filament left in the extruder by pulling it upward."
        '';
      };

      # AUTOMATIC BED MESH LOAD when starting ANY print, whatever its source (screen, Fluidd or the slicer): Moonraker starts jobs with SDCARD_PRINT_FILE, and this macro wraps it (rename_existing) to load the saved mesh first. This way whoever prints does not have to remember anything or configure the slicer's start G-code. The G28 from the slicer does NOT clear the mesh (only BED_MESH_CLEAR does). If there is no saved mesh, it warns and prints anyway (without correction).
      "gcode_macro SDCARD_PRINT_FILE" = {
        description = "Starts a print, loading the saved bed mesh first";
        rename_existing = "SDCARD_PRINT_FILE_BASE";
        gcode = macro ''
          {% if '${cfg.mesh.profile}' in printer.bed_mesh.profiles %}
            BED_MESH_PROFILE LOAD=${cfg.mesh.profile}
          {% else %}
            RESPOND TYPE=error MSG="Warning: there is no saved bed mesh. The first layer may come out uneven. Let the printer owner know."
          {% endif %}
          SDCARD_PRINT_FILE_BASE {rawparams}
        '';
      };
    };
  };
}
