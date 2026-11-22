{ config, lib, ... }:

# Workarounds for 32-bit ARM (armv7l), applied only when the system is armv7l (`nixpkgs.hostPlatform`). They exist because some packages do not build for that architecture, or do not cross-compile to it: a 64-bit board gets the packages as nixpkgs defines them.
#
# The condition reads the option and not `pkgs`, because `pkgs` is built from the overlays defined here.
lib.mkIf config.nixpkgs.hostPlatform.isArmv7 {
  # `mkAfter`: these overrides build on the ones in klipper.nix and klipperscreen.nix, so they must come later in the overlay list.
  nixpkgs.overlays = lib.mkAfter [
    # Klipper without numpy and matplotlib. The nixpkgs package includes numpy (and matplotlib for klipper-calibrate-shaper). numpy drags in openblas, which does not cross-compile for armv7l (VFP D32 vs. D16 ABI asm kernels). They are only needed to calibrate input shaper with an accelerometer: Klipper imports numpy only when using [resonance_tester]/[adxl345]. The environment is redeclared without them (with msgspec, which v0.14.0 adds) and the calibration script says it is not available.
    (final: prev: {
      klipper = prev.klipper.overrideAttrs (old: {
        buildInputs = [
          (final.python3.withPackages (p: with p; [
            python-can cffi pyserial greenlet jinja2 markupsafe msgspec
          ]))
        ];
        pythonInterpreter = "";
        pythonScriptWrapper = final.writeShellScript "klipper-calibrate-shaper" ''
          echo "klipper-calibrate-shaper is not available in this image (no numpy/matplotlib)" >&2
          exit 1
        '';
      });
    })

    # sdbus does not cross-compile: its setup.py runs `pkg-config` without a prefix and when cross-compiling only `<triple>-pkg-config` exists. A link with the unprefixed name is added, only for the build.
    (final: prev: {
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (pyfinal: pyprev: {
          sdbus = pyprev.sdbus.overrideAttrs (old: {
            preBuild = (old.preBuild or "") + ''
              mkdir -p "$TMPDIR/pkg-config-shim"
              ln -s "$(type -P ${final.stdenv.cc.targetPrefix}pkg-config)" "$TMPDIR/pkg-config-shim/pkg-config"
              export PATH="$TMPDIR/pkg-config-shim:$PATH"
            '';
          });
        })
      ];
    })

    # KlipperScreen without the camera panel: `mpv` is removed because libmpv drags in yt-dlp -> deno (does not exist for armv7l) and ffmpeg. The panel fails if it is opened; the rest works.
    (final: prev: {
      klipperscreen = prev.klipperscreen.overrideAttrs (old:
        let
          withoutMpv = lib.filter (p: (p.pname or "") != "mpv");
          pythonPath = withoutMpv (old.pythonPath or [ ]);
        in
        {
          inherit pythonPath;
          propagatedBuildInputs = withoutMpv (old.propagatedBuildInputs or [ ]);
          # buildPythonApplication also copies pythonPath into buildInputs.
          buildInputs = withoutMpv (old.buildInputs or [ ]);
          # The recipe does `--set PYTHONPATH "$PYTHONPATH"`, and when cross-compiling that $PYTHONPATH includes the Python of the builder's platform: nixpkgs forbids it (disallowedReferences) and the build fails at the end. It is assembled only with the armv7l packages.
          preFixup = ''
            mkdir -p $out/bin
            cp -r . $out/dist
            gappsWrapperArgs+=(--set PYTHONPATH "${final.python3.pkgs.makePythonPath pythonPath}")
            wrapGApp $out/dist/screen.py
            ln -s $out/dist/screen.py $out/bin/KlipperScreen
          '';
        });
    })
  ];
}
