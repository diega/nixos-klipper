{ config, lib, pkgs, ... }:

# Networking with NetworkManager: it is what KlipperScreen's network panel talks to (over D-Bus), which lets you scan and connect to new Wi-Fi networks from the touchscreen. Connections that are added (from the screen or with `nmcli`) are stored in /etc/NetworkManager/system-connections and survive rebuilds, so no Wi-Fi key lives in the repo.
#
# Ethernet (LAN9514) and Wi-Fi via USB dongle (the kernel has drivers for Realtek, Ralink, MediaTek, Atheros...). Classic interface names (eth0/wlan0).
{
  networking.usePredictableInterfaceNames = false;

  # ETHERNET (eth0) -> systemd-networkd, NOT NetworkManager.
  #
  # Why: NetworkManager's wired connection fails on a direct cable with no DHCP server or IPv6 announcements: after 45 s of DHCP it gives `ip-config-unavailable`, removes ALL addresses from eth0 and waits 5 minutes before retrying. Result: a cycle of ~45 s reachable / 5 min unreachable with the cable plugged in (it is not suspend: there are no link or USB events).
  #
  # networkd has no "activation failure": the link-local addresses are always set, with or without DHCP, and DHCP keeps being retried in the background.
  #
  # Deliberately generic: it works for ANYTHING plugged in by cable, without a fixed IP (a fixed IP would only work with a peer that uses that same network):
  #   - router / DHCP server          -> address via DHCP
  #   - direct cable without DHCP     -> IPv4 link-local 169.254.x.x (the default used by Windows, macOS and Linux) and IPv6 link-local; they can talk without config.
  #   - IPv4 link-local turns on "when DHCP does not respond for a while", and DHCP keeps being retried in parallel (systemd.network(5), LinkLocalAddressing=).
  systemd.network = {
    enable = true;
    networks."10-eth0" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        DHCP = "ipv4";
        # yes = IPv6 link-local + IPv4 link-local (DHCP fallback).
        LinkLocalAddressing = "yes";
        # fe80::<EUI-64 derived from the MAC>: fixed, does not change between boots or rebuilds.
        IPv6LinkLocalAddressGenerationMode = "eui64";
      };
      dhcpV4Config.RouteMetric = 100;
      linkConfig.RequiredForOnline = "no";
    };
  };
  networking.useDHCP = false;
  networking.dhcpcd.enable = false;

  # WI-FI (wlan0) -> NetworkManager: it is what KlipperScreen's network panel talks to.
  networking.networkmanager = {
    enable = true;
    # NetworkManager does not touch eth0 (networkd manages it, above).
    unmanaged = [ "interface-name:eth0" ];
    # No VPN plugins (openvpn, vpnc...): they bloat the image and are not used.
    plugins = lib.mkForce [ ];
    # No Wi-Fi power saving: the priority is that the network does not drop, not consumption.
    wifi.powersave = false;
    # No PMF (management frame protection) by default. WPA2+WPA3 routers advertise SAE and wpa_supplicant prefers it ("Using SAE auth_alg"), but SAE requires PMF and the `rtl8xxxu` driver (RTL8188EUS dongles) does not support it: association fails ("association took too long", CONN_FAILED) without ever getting to try WPA2. With pmf=1 (disable) it uses WPA2-PSK and connects. It applies to the new networks added from the KlipperScreen panel; it only leaves out pure WPA3 networks, which those dongles cannot use either.
    settings.connection."wifi-sec.pmf" = 1;
  };

  # Stop anything from putting the Pi or the USB buses to sleep (the Pi 2's Ethernet chip is a USB device).
  boot.kernelParams = lib.mkBefore [ "usbcore.autosuspend=-1" ];
  powerManagement.enable = false;
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # NetworkManager starts only once wpa_supplicant is already up. On boot wpa_supplicant restarts (killed ~1 s after starting and back at 26 s) and NetworkManager, which requests it over D-Bus, would fall into that gap: it would log `device (wlan0): Couldn't initialize supplicant interface: Failed to D-Bus activate wpa_supplicant service` (ERROR level) before recovering on its own.
  systemd.services.NetworkManager = {
    wants = [ "wpa_supplicant.service" ];
    after = [ "wpa_supplicant.service" ];
  };

  # No modem: ModemManager is enabled together with NetworkManager and is not needed.
  networking.modemmanager.enable = lib.mkForce false;

  # avahi-daemon died with SIGSYS in `setgroups` on armv7l: its unit's system call filter (@system-service) blocks the 32-bit variant that ARM uses. It is an unprivileged mDNS daemon; the filter is removed instead of enumerating calls.
  systemd.services.avahi-daemon.serviceConfig.SystemCallFilter = lib.mkForce [ ];

  # klipper.local via mDNS.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = false;
    };
  };

  # Firewall: only the ports in use are open (SSH, nginx, Moonraker, camera stream).
  networking.firewall.allowedTCPPorts = [ 22 80 7125 8080 ];

  hardware.wirelessRegulatoryDatabase = true;
}
