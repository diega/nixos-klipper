{ config, lib, pkgs, sources, ... }:

# KlipperScreen v0.4.7 (flake input `klipperscreen-src`; nixpkgs 26.05 ships 0.4.5) on X with the fbdev driver on the TFT (/dev/fb1). It is GTK3, so it only exists in the `klipper-full` variant. The display chain is:
#   piscreen (rotate=270) -> fbcon rotate:2 (display.nix) -> X fbdev "Rotate UD" -> libinput matrix.
lib.mkIf config.nixosKlipper.klipperscreen.enable (
  let
    conf = pkgs.writeText "KlipperScreen.conf" ''
      # Declared defaults. What the user changes on the screen is saved in the writable copy (see stateConf).
      [main]
      use_dpms = False
      print_sort_dir = date_desc
    '';
    # KlipperScreen saves what the user changes on the screen (language, brightness, sort order...) by writing into the file given with `-c`. That file cannot be the Nix store one (read-only: every change would be lost on the next restart, `Error writing configuration file ... Read-only file system`), so it is a writable copy in /var/lib/klipperscreen: at each start it is rebuilt from the declared `conf` above PLUS the auto-generated section KlipperScreen appended last time (everything below its `#~# --- Do not edit below this line` marker), so the declared defaults can change with a deploy while the user's choices on the screen survive reboots and deploys.
    stateConf = "/var/lib/klipperscreen/KlipperScreen.conf";
    prepareConf = pkgs.writeShellScript "klipperscreen-prepare-config" ''
      f=${stateConf}
      saved=""
      if [ -f "$f" ]; then
        saved=$(${pkgs.gnused}/bin/sed -n '/^#~# --- Do not edit below this line/,$p' "$f")
      fi
      ${pkgs.coreutils}/bin/cat ${conf} > "$f.new"
      if [ -n "$saved" ]; then
        printf '\n%s\n' "$saved" >> "$f.new"
      fi
      ${pkgs.coreutils}/bin/mv "$f.new" "$f"
    '';
    # Python dependency that is dropped: dbus-python, which no KlipperScreen module imports. sdbus and sdbus-networkmanager are KEPT: they are the network panel (network.py). (On 32-bit ARM, modules/armv7l.nix also drops mpv.)
    dropped = [ "dbus-python" ];
    withoutDropped = lib.filter (p: !(builtins.elem (p.pname or "") dropped));
  in
  {
    nixpkgs.overlays = [
      (final: prev: {
        klipperscreen = prev.klipperscreen.overrideAttrs (old:
          let
            pythonPath = withoutDropped (old.pythonPath or [ ]);
          in
          {
            version = "0.4.7";
            src = sources.klipperscreen-src;
            inherit pythonPath;
            propagatedBuildInputs = withoutDropped (old.propagatedBuildInputs or [ ]);
            # buildPythonApplication also copies pythonPath into buildInputs.
            buildInputs = withoutDropped (old.buildInputs or [ ]);
            # Network panel (with ~65 networks in view):
            #  1. `get_networks()` reads each access point over D-Bus and, if NetworkManager removes one in the middle, it throws `Object does not exist at path .../AccessPoint/N` and the panel is left EMPTY (it is in /tmp/KlipperScreen.log).
            #  2. It is extremely slow: `is_known()` for each AP re-reads all saved profiles (one call = 2.3 s) and `add_network` requests the full list AGAIN for EACH network: ~150 s with the screen frozen when opening the panel.
            # The patch reads the profiles once, skips the APs that disappear and reuses the list. Cause (measured on the Pi): each D-Bus call is cheap (~3 ms) but 0.4.7 makes a number of calls that grows with the SQUARE of the visible APs (tens of thousands with 65+ APs, ~150 s to open the panel). Upstream fixed it on master (commit a451d9d98, issue #1788, PR #1789) but there is no tagged release after v0.4.7 yet. RETIRE THIS PATCH when KlipperScreen tags a release that contains that commit (bump klipperscreen-src in flake.nix, and re-check the `api_key` substituteInPlace below, which no longer exists on master). Note: the patch text is part of the derivation; editing it rebuilds KlipperScreen.
            patches = (old.patches or [ ]) ++ [ ../patches/klipperscreen-0.4.7-robust-network-list.patch ];
            # KlipperScreen ALWAYS sends `"api_key": ""` in `server.connection.identify` when no key is configured, and Moonraker 0.11 treats the empty string as an invalid key (`validate_api_key("")` -> "Invalid API Key") and REVOKES the trust of the local connection: afterwards everything gives `Unauthorized` (no data or file list on the screen). The field is omitted when it is empty, so there is no need to store Moonraker's (secret) key in the repo. `--replace-fail` breaks the build if a new KlipperScreen version changes that line.
            postPatch = (old.postPatch or "") + ''
              substituteInPlace ks_includes/KlippyWebsocket.py \
                --replace-fail '"api_key": f"{api_key}"' '**({"api_key": api_key} if api_key else {})'
            '';
          });
      })
    ];

    services.xserver = {
      enable = true;
      autorun = false;
      exportConfiguration = true;
      xkb.layout = "us";

      # The video driver, the screen and the touch calibration come from the board module (display.nix).
    };
    services.libinput.enable = true;

    # Enabling services.xserver turns on "graphical-desktop" (pipewire -> ffmpeg, mesa -> llvm, speech-dispatcher, icons...) and lightdm. None of them is needed: X only serves KlipperScreen over fbdev, without GL. Without this the image drags in ffmpeg and llvm, which are impractical to cross-compile.
    services.graphical-desktop.enable = lib.mkForce false;
    services.xserver.displayManager.lightdm.enable = lib.mkForce false;
    services.xserver.desktopManager.xterm.enable = lib.mkForce false;
    # DejaVu: GTK's default sans. Free Mono: the only family that KlipperScreen's CSS names (styles/base.css, `font-family: Free Mono`, the console font).
    fonts.packages = [ pkgs.dejavu_fonts pkgs.freefont_ttf ];
    # GTK3 is in the system-path and its hook rebuilds the icon cache with `find $out/share/icons`, which fails if no package provides that directory (hicolor does).
    xdg.icons.enable = true;

    users.users.klipperscreen = {
      isSystemUser = true;
      group = "klipperscreen";
      # networkmanager: lets the network panel add and activate Wi-Fi connections (NetworkManager polkit rules for that group).
      extraGroups = [ "video" "input" "tty" "networkmanager" ];
      # DEPLOY RACE FIX (with stopIfChanged below). The service's only logind session ends when the unit is stopped, and logind removes the user (and its user@997 manager) 10 s later (UserStopDelaySec). On this slow Pi the 10 s expire while switch-to-configuration-ng is walking the logind users, so it either sees the user vanish (`Failed to get GID for klipperscreen ... Unknown object /org/freedesktop/login1/user/_997`, exit 1, new generation active but klipperscreen left stopped) or reloads a manager that dies half way (exit 4). Lingering keeps user 997 and its manager alive, so the object always exists.
      linger = true;
    };
    users.groups.klipperscreen = { };

    systemd.services.klipperscreen = {
      description = "KlipperScreen";
      wantedBy = [ "multi-user.target" ];
      after = [ "moonraker.service" "systemd-logind.service" ];
      wants = [ "moonraker.service" ];
      # Without this, logind opens the session as `user-light` (no user manager or bus), and `switch-to-configuration` fails when reloading klipperscreen's user units (`Unable to autolaunch a dbus-daemon`) and exits with code 4: the system is left properly activated, but the WHOLE `nixos-rebuild switch` ends up reporting an error. With class `user` there is a bus and it exits cleanly.
      environment.XDG_SESSION_CLASS = "user";
      # Restart at the END of the switch instead of stopping at the beginning: during the user-walking step the old session is still alive, and the screen is never left stopped if the switch aborts for another reason. (Root cause analysis: switch-to-configuration-ng main.rs, do_system_switch, user loop; upstream fix for the GID lookup is nixpkgs PR #550361, not in 26.05. The two settings above/here make it unnecessary.)
      stopIfChanged = false;
      serviceConfig = {
        User = "klipperscreen";
        PAMName = "login";
        # X without root needs virtual terminal 7 to be ITS controlling terminal. `TTYPath` alone does nothing: `StandardInput = tty-fail` is needed, which opens that terminal, makes it the controlling terminal and gives ownership to the service user. Without it X fails with `xf86OpenConsole: Cannot open virtual console 7 (Permission denied)`. It is the same pattern NixOS's `services.cage` unit uses.
        StandardInput = "tty-fail";
        StandardOutput = "journal";
        StandardError = "journal";
        TTYPath = "/dev/tty7";
        # Xorg without root writes its log to ~/.local/share/xorg, and this system user's HOME (/var/empty) is not writable: X exits with error 1 without leaving any message unless an explicit `-logfile` is given. /run/klipperscreen/Xorg.log stays readable for debugging.
        RuntimeDirectory = "klipperscreen";
        StateDirectory = "klipperscreen";
        # Moonraker takes a while to open 7125 on this Pi (tens of seconds on a cold boot, and ~1 min if it is restarted). KlipperScreen exhausts its retries and stays on the "Cannot connect to Moonraker ... Connection refused" banner until Retry is tapped. It waits for the port (max 3 min; if it does not open, it starts anyway).
        ExecStartPre = [
          prepareConf
          (pkgs.writeShellScript "wait-for-moonraker" ''
            for _ in $(seq 180); do
              (exec 3<>/dev/tcp/127.0.0.1/7125) 2>/dev/null && exit 0
              sleep 1
            done
            exit 0
          '')
        ];
        TimeoutStartSec = 240;
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
        UtmpIdentifier = "tty7";
        UtmpMode = "user";
        Restart = "always";
        RestartSec = 2;
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.xorg.xinit}/bin/xinit"
          "${pkgs.klipperscreen}/bin/KlipperScreen -c ${stateConf}"
          "--"
          "${pkgs.xorg.xorgserver}/bin/Xorg :0 vt7 -keeptty -nolisten tcp -config /etc/X11/xorg.conf -logfile /run/klipperscreen/Xorg.log"
        ];
      };
    };
  }
)
