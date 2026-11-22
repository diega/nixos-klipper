{ ... }:

{
  swapDevices = [{ device = "/var/swapfile"; size = 512; }];

  # HARDWARE watchdog of the SoC (BCM2835): /dev/watchdog exists and the driver is in the kernel (CONFIG_BCM2835_WDT=y); systemd arms it. If the system hangs and stops "petting" it, the Pi reboots by itself. 15 s is the maximum this hardware supports.
  systemd.watchdog.runtimeTime = "15s";

  services.klipper.settings = {
    # Pi's processor temperature (SoC sensor), visible in Fluidd and KlipperScreen.
    "temperature_sensor raspberry_pi" = {
      sensor_type = "temperature_host";
      sensor_path = "/sys/class/thermal/thermal_zone0/temp";
      min_temp = 10;
      max_temp = 100;
    };
  };
}
