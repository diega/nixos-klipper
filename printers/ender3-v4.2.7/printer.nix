{ ... }:

# Declarative printer.cfg: Ender 3 with a Creality v4.2.7 board (STM32F103). The SAVE_CONFIG block that Klipper writes (PID, meshes...) is kept across rebuilds; what is written here takes precedence over the rest.
#
# MCU firmware: not touched. The Pi talks to the board via the CH340 (UART on USART1, 250000 baud, default), not via native USB.
{
  services.klipper.settings = {
    # Fluidd macros (PAUSE, RESUME, CANCEL_PRINT, ...). klipper.nix links fluidd.cfg.
    "include fluidd.cfg" = { };

    stepper_x = {
      step_pin = "PB9";
      dir_pin = "PC2";
      enable_pin = "!PC3";
      microsteps = 16;
      rotation_distance = 40;
      endstop_pin = "^PA5";
      position_endstop = 3;
      position_max = 235;
      homing_speed = 50;
    };

    stepper_y = {
      step_pin = "PB7";
      dir_pin = "PB8";
      enable_pin = "!PC3";
      microsteps = 16;
      rotation_distance = 40;
      endstop_pin = "^PA6";
      # Max length on Y: 205 mm
      position_min = -7;
      position_endstop = -7;
      position_max = 198;
      homing_speed = 50;
    };

    stepper_z = {
      step_pin = "PB5";
      dir_pin = "!PB6";
      enable_pin = "!PC3";
      microsteps = 16;
      rotation_distance = 8;
      endstop_pin = "^PA7";
      position_endstop = 0;
      position_max = 250;
    };

    extruder = {
      max_extrude_only_distance = 100.0;
      step_pin = "PB3";
      dir_pin = "PB4";
      enable_pin = "!PC3";
      microsteps = 16;
      rotation_distance = 33.683;
      nozzle_diameter = 0.400;
      filament_diameter = 1.750;
      heater_pin = "PA1";
      sensor_type = "EPCOS 100K B57560G104F";
      sensor_pin = "PC5";
      control = "pid";
      pid_Kp = 21.527;
      pid_Ki = 1.063;
      pid_Kd = 108.982;
      min_temp = 0;
      max_temp = 250;
    };

    heater_bed = {
      heater_pin = "PA2";
      sensor_type = "EPCOS 100K B57560G104F";
      sensor_pin = "PC4";
      control = "pid";
      pid_Kp = 54.027;
      pid_Ki = 0.770;
      pid_Kd = 948.182;
      min_temp = 0;
      max_temp = 130;
    };

    fan.pin = "PA0";

    mcu = {
      serial = "/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0";
      restart_method = "command";
    };

    printer = {
      kinematics = "cartesian";
      max_velocity = 300;
      max_accel = 3000;
      max_z_velocity = 5;
      max_z_accel = 100;
    };

    bed_screws = {
      screw1 = "30.5, 37";
      screw2 = "30.5, 207";
      screw3 = "204.5, 207";
      screw4 = "204.5, 37";
    };

    # A list is serialized as a multiline value with indentation (a string with \n is not indented).
    board_pins.aliases = [
      "EXP1_1=PC6,EXP1_3=PB10,EXP1_5=PB14,EXP1_7=PB12,EXP1_9=<GND>,"
      "EXP1_2=PB2,EXP1_4=PB11,EXP1_6=PB13,EXP1_8=PB15,EXP1_10=<5V>,"
      "PROBE_IN=PB0,PROBE_OUT=PB1,FIL_RUNOUT=PA4"
    ];

    # Moonraker (NixOS) stores gcodes in /var/lib/moonraker/gcodes.
    virtual_sdcard = {
      path = "/var/lib/moonraker/gcodes";
      on_error_gcode = "CANCEL_PRINT";
    };

    safe_z_home = {
      home_xy_position = "117.5,117.5";
      speed = 50;
      # Lifts 15 mm BEFORE moving X/Y in any G28. The bed glass is held by clips at the corners (the front ones stick out ~12 mm over the glass): without this lift, the X/Y sweep during homing would pass over them at whatever height the nozzle is at.
      z_hop = 15;
      z_hop_speed = 5;
    };

    # BL-Touch (bed leveling probe). Wiring: the 5 wires on the "BL-T" connector of the Creality 4.2.7 board (G, V, IN, G, OUT): signal = PB1 (OUT), pin control = PB0 (IN). The Z endstop (PA7) is NOT touched and is still the one G28 uses (see stepper_z and safe_z_home).
    #
    # Looking at the printer from the front, the sensor is 45 mm to the LEFT of the nozzle and 3 mm FORWARD (hence the negative offsets). z_offset = 3.92 mm is the nozzle height above the bed when the probe triggers. It comes from a paper test (PROBE_CALIBRATE, cold nozzle, plain paper): the paper drags at Z=0.33 and the probe triggers at Z=4.2545 (average of 10 passes; PROBE_ACCURACY range 0.0125 mm, deviation 0.004 mm), so 4.2545 - 0.33 = 3.92. It is high (typically 2 to 2.5 mm): the sensor is mounted lower than usual. If the bracket is replaced or the nozzle is changed, the calibration must be repeated. To fine-tune the first layer without recalibrating, use the live Z adjustment in Fluidd/KlipperScreen.
    bltouch = {
      sensor_pin = "^PB1";
      control_pin = "PB0";
      x_offset = -45;
      y_offset = -3;
      z_offset = 3.92;
    };

    # Mesh auto-leveling. mesh_min/mesh_max are coordinates of the PROBE (not the nozzle): with the sensor 45 mm to the left of the nozzle, the probe only reaches X 0..190 (the nozzle reaches 235) and Y up to ~195, so the last ~30 mm on the right side of the bed are not measured. 5x5 = 25 points; horizontal_move_z = 6 stays above the trigger height (z_offset 3.92). MESH LIMITS and the glass clips: there are clips at all 4 corners (2 front, 2 back). The front ones stick out ~12 mm over the glass. With the probe 45 mm left of the nozzle and 3 mm behind it, a first mesh row at Y=10 would land right on the front-left clip. A wide margin is used, not the bare minimum: the first row at Y=25 (probe ~13 mm from the clip edge, nozzle ~16 mm) tolerates deeper or shifted clips; the right edge at X=180 leaves the nozzle at 225, 10 mm from the machine's limit (235). At the back the nozzle (Y=193) is ~3 cm from the clip line, so Y=190 is fine. If the clips or their location change, review this.
    bed_mesh = {
      speed = 120;
      horizontal_move_z = 6;
      mesh_min = "10,25";
      mesh_max = "180,190";
      probe_count = "5,5";
      algorithm = "bicubic";
      # The correction is faded out between Z=1 and Z=10 mm so the deformation is not carried over to the whole part.
      fade_start = 1;
      fade_end = 10;
    };
  };
}
