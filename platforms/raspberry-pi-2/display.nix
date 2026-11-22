{ ... }:

# Kernel parameters for the TFT. The `piscreen` overlay (config.txt, see boot.nix) creates /dev/fb1 (fb_ili9486) and the ADS7846 touch (event1); the overlay's defaults are used: rotate=270, SPI at 24 MHz, 30 fps and touch with swapped axes.
{
  boot.kernelParams = [
    "console=ttyAMA0,115200"
    # The last console= is the main one: text on the TFT.
    "console=tty1"
    # Text console on fb1 (the TFT) instead of fb0, and rotated 180°.
    "fbcon=map:1"
    "fbcon=rotate:2"
  ];

  # X on the TFT: the framebuffer driver on /dev/fb1 rotated to match fbcon, and the touch matrix.
  # The chain is: piscreen (rotate=270) -> fbcon rotate:2 -> X fbdev "Rotate UD" -> libinput matrix.
  services.xserver = {
    videoDrivers = [ "fbdev" ];

    # /etc/X11/xorg.conf.d/99-fbdev.conf
    deviceSection = ''
      Option "fbdev" "/dev/fb1"
      Option "Rotate" "UD"
    '';
    monitorSection = ''
      HorizSync 30-80
      VertRefresh 60
    '';
    screenSection = ''
      DefaultDepth 16
      SubSection "Display"
        Depth 16
        Modes "480x320"
      EndSubSection
    '';

    # /etc/X11/xorg.conf.d/99-touchscreen-libinput.conf. Matrix calibrated with xtcal.
    inputClassSections = [
      ''
        Identifier "Calibrated Touchscreen"
        MatchProduct "ADS7846 Touchscreen"
        Driver "libinput"
        Option "TransformationMatrix" "-1.104286 0.016416 1.051831 0.012756 1.132581 -0.079052 0 0 1"
      ''
    ];
  };

  nixpkgs.overlays = [
    # The X fbdev driver for the framebuffer uses functions from the `fbdevhw` module that X loads AFTER the driver. nixpkgs builds it with immediate binding (BIND_NOW, hardening by default) and X fails to load it: `fbdev_drv.so: undefined symbol: fbdevHWSave`. With lazy binding it works.
    (final: prev: {
      xf86-video-fbdev = prev.xf86-video-fbdev.overrideAttrs (old: {
        hardeningDisable = (old.hardeningDisable or [ ]) ++ [ "bindnow" ];
      });
    })
  ];
}
