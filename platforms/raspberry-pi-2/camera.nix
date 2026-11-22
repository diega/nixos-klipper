{ config, lib, pkgs, ... }:

# CSI camera (OV5647, the Pi Camera v1) through the OLD GPU stack, with µStreamer.
#
# Why this stack and not libcamera/camera-streamer: with `start_x=1` the GPU firmware (VideoCore IV) drives the sensor, does the image processing (ISP) and ENCODES THE JPEG itself; the kernel only exposes a /dev/video0 that already delivers MJPEG. The CPU barely works (it passes the frames through as they are). The kernel module is `bcm2835_v4l2` (CONFIG_VIDEO_BCM2835=m). NO libcamera overlay is loaded (`camera_auto_detect`, `dtoverlay=ov5647`): it would clash with this stack over the camera's I2C bus.
#
# µStreamer serves on 127.0.0.1:8080, which is where nginx (moonraker.nix) expects the stream at /webcam/.
let
  # No Janus (WebRTC: it drags in janus-gateway -> ffmpeg -> mbedtls/libajantv2, which do not build for armv7l) nor the Python bindings: plain MJPEG over HTTP does not need them.
  ustreamer = (pkgs.ustreamer.override { withJanus = false; withPython = false; }).overrideAttrs (old: {
    # With an MJPEG source, ustreamer tries to set the encoder quality in hardware via VIDIOC_G_JPEGCOMP; the GPU camera (bcm2835) does not support it and logs it as an ERROR on every boot. It is harmless (the JPEG is already encoded and is forwarded as is): it is lowered to INFO.
    postPatch = (old.postPatch or "") + ''
      sed -i '/HW encoding quality parameters/s/_LOG_ERROR/_LOG_INFO/' src/libs/capture.c
      if grep -q '_LOG_ERROR.*HW encoding quality' src/libs/capture.c; then
        echo "the ustreamer patch did not apply (did the source change?)" >&2; exit 1
      fi
    '';
  });
in
lib.mkIf config.nixosKlipper.camera.enable {
  # start_x.elf/fixup_x.dat are copied by the boot hook (boot.nix) along with the normal ones.
  nixosKlipper.boot.extraConfigTxt = ''
    # Camera via the GPU: firmware with camera support and memory for the ISP/encoder.
    start_x=1
    gpu_mem=128
  '';

  boot.kernelModules = [ "bcm2835_v4l2" ];

  # v4l2-ctl for diagnostics. Without the GUI (qv4l2 drags in Qt, which does not build for armv7l) nor BPF.
  environment.systemPackages = [ (pkgs.v4l-utils.override { withGUI = false; withBPF = false; }) ];

  systemd.services.ustreamer = {
    description = "µStreamer (CSI camera via the GPU)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    # With no camera connected there is no /dev/video0: do not retry in a loop.
    unitConfig.ConditionPathExists = "/dev/video0";
    serviceConfig = {
      DynamicUser = true;
      SupplementaryGroups = [ "video" ];
      Restart = "always";
      RestartSec = 5;
      ExecStart = lib.concatStringsSep " " [
        "${ustreamer}/bin/ustreamer"
        "--device=/dev/video0"
        # GPU-encoded MJPEG: ustreamer forwards it without re-encoding.
        "--format=MJPEG"
        # 640x480 at 15 fps.
        "--resolution=640x480 --desired-fps=15"
        # With nobody watching it drops to ~1 fps (lower consumption).
        "--slowdown"
        "--host=127.0.0.1 --port=8080"
      ];
    };
  };
}
