{ lib, ... }:

{
  options.nixosKlipper = {
    admin = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "printer";
        description = "Name of the administrator account (SSH key login only, `wheel` group, sudo without a password).";
      };
      authorizedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "ssh-ed25519 AAAA... me@laptop" ];
        description = "Public SSH keys allowed to log in as the administrator. When empty, no account is created and you define your own users.";
      };
    };

    regulatoryDomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "US";
      description = "Two-letter Wi-Fi regulatory domain of your country (sets `cfg80211.ieee80211_regdom`). Unset leaves the kernel's default.";
    };

    klipperscreen.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        KlipperScreen on the SPI touchscreen. It is a GTK3 app that also needs X;
        it is mandatory in this install, the switch only exists for test builds.
      '';
    };
  };
}
