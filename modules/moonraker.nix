{ config, lib, pkgs, sources, ... }:

# Moonraker + Fluidd (nginx). No [update_manager]: on NixOS the versions are pinned by flake.lock.
{
  # Moonraker v0.11.0 (flake input `moonraker-src`; nixpkgs 26.05 ships 0.10.0). Its Python dependencies are the same as 0.10.0's (only the version caps changed).
  #
  # nixpkgs' Moonraker includes pycurl, but per its changelog ("Moonraker no longer uses Tornado's curl based http client") nothing uses it. When cross-compiling, pycurl links against the libcurl of the builder's platform and does not build.
  nixpkgs.overlays = [
    (final: prev: {
      moonraker = prev.moonraker.overrideAttrs (old:
        let
          pythonEnv = final.python3.withPackages (p: with p; [
            tornado pyserial-asyncio pillow lmdb streaming-form-data distro inotify-simple
            libnacl paho-mqtt zeroconf preprocess-cancellation jinja2 dbus-fast apprise
            python-periphery ldap3 importlib-metadata
          ]);
        in
        {
          version = "0.11.0";
          src = sources.moonraker-src;
          installPhase = ''
            mkdir -p $out $out/bin $out/lib
            cp -r moonraker $out/lib

            makeWrapper ${pythonEnv}/bin/python $out/bin/moonraker \
              --add-flags "$out/lib/moonraker/moonraker.py"
          '';
        });
    })
  ];

  services.moonraker = {
    enable = true;
    address = "0.0.0.0";
    port = 7125;
    # Restart/power off the Pi from Fluidd (via polkit).
    allowSystemControl = true;
    settings = {
      authorization = {
        trusted_clients = [
          "10.0.0.0/8"
          "127.0.0.0/8"
          "169.254.0.0/16"
          "172.16.0.0/12"
          "192.168.0.0/16"
          "FC00::/7"
          "FE80::/10"
          "::1/128"
        ];
        cors_domains = [
          "*.lan"
          "*.local"
          "*://localhost"
          "*://localhost:*"
          "*://my.mainsail.xyz"
          "*://app.fluidd.xyz"
        ];
      };
      octoprint_compat = { };
      history = { };
    };
  };

  # Moonraker 0.11 groups everything under its data directory and marks `file_manager.config_path` as deprecated. The "config" root that Fluidd sees is /var/lib/moonraker/config: printer.cfg and fluidd.cfg are linked there, which Klipper keeps reading from /var/lib/klipper (the relative `include fluidd.cfg` does not change).
  #
  # `logs/` is created here because Moonraker opens its log file BEFORE creating its folders: on the first boot of a new image it would warn "Unable to create log file".
  systemd.tmpfiles.rules = [
    "d /var/lib/moonraker/logs 0755 moonraker moonraker - -"
    "d /var/lib/moonraker/config 0755 moonraker moonraker - -"
    "L+ /var/lib/moonraker/config/printer.cfg - - - - /var/lib/klipper/printer.cfg"
    "L+ /var/lib/moonraker/config/fluidd.cfg - - - - /var/lib/klipper/fluidd.cfg"
  ];

  security.polkit.enable = true;

  # Moonraker talks to Klipper over /run/klipper/api, which belongs to the klipper group.
  users.users.moonraker.extraGroups = [ "klipper" ];

  services.fluidd = {
    enable = true;
    hostName = "klipper";
    # nixpkgs' package builds Fluidd with npm (nodejs for armv7l: hours, and it runs out of memory). It is a static web app, so the prebuilt release is used (flake input `fluidd-release`, v1.38.1; nixpkgs ships 1.36.2).
    package = pkgs.runCommand "fluidd-1.38.1" { } ''
      mkdir -p $out/share/fluidd/htdocs
      cp -r ${sources.fluidd-release}/. $out/share/fluidd/htdocs/
    '';
    nginx = {
      # Responds by IP or by any name (`server_name _`).
      default = true;
      extraConfig = ''
        # No upload limit (large gcodes) or request buffering.
        client_max_body_size 0;
        proxy_request_buffering off;
      '';
      # Camera streams (crowsnest/camera-streamer); without a camera they return 502.
      locations."/webcam/" = {
        proxyPass = "http://127.0.0.1:8080/";
        extraConfig = ''
          postpone_output 0;
          proxy_buffering off;
          proxy_ignore_headers X-Accel-Buffering;
          access_log off;
          # NOTE: `error_log off;` does NOT disable anything: nginx takes it as the NAME OF A FILE ("off") and fails to open it in the package directory, which is read-only on NixOS.
          error_log /dev/null crit;
        '';
      };
    };
  };
}
