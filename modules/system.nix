{ config, lib, pkgs, ... }:

let
  cfg = config.nixosKlipper;
in
{
  # The administrator account, only when it has at least one SSH key.
  users.users = lib.mkIf (cfg.admin.authorizedKeys != [ ]) {
    ${cfg.admin.name} = {
      isNormalUser = true;
      extraGroups = [ "wheel" "dialout" "video" "input" ];
      openssh.authorizedKeys.keys = cfg.admin.authorizedKeys;
    };
  };
  security.sudo.wheelNeedsPassword = lib.mkIf (cfg.admin.authorizedKeys != [ ]) false;

  boot.kernelParams = lib.optional (cfg.regulatoryDomain != null) "cfg80211.ieee80211_regdom=${cfg.regulatoryDomain}";

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # No RTC: timesyncd saves the time and restores it on boot.
  services.timesyncd.enable = true;

  # D-Bus: dbus-broker logs 4 errors on every boot (`Ignoring duplicate name ...`: wpa_supplicant, nm_dispatcher, nm_priv_helper, PolicyKit1) because those service files exist both in their own package and in system-path. Classic D-Bus (services.dbus.implementation = "dbus") would avoid it, but it adds a setuid wrapper compiled with musl and that means building the whole armv7l musl toolchain on the builder (hours). Instead only the duplicated files are removed from system-path; the services stay available from their packages, which are listed in the broker's service directories.
  environment.extraSetup = ''
    for f in fi.w1.wpa_supplicant1 org.freedesktop.nm_dispatcher org.freedesktop.nm_priv_helper org.freedesktop.PolicyKit1; do
      rm -f "$out/share/dbus-1/system-services/$f.service"
    done
  '';

  # To receive closures from the Mac with `nixos-rebuild --target-host`.
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
  };

  environment.systemPackages = with pkgs; [ rsync git htop tmux usbutils ];
}
