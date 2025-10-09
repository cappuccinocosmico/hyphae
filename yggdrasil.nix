{ config, lib, pkgs, ... }:

{
  # Enable Yggdrasil mesh networking
  services.yggdrasil = {
    enable = true;
    persistentKeys = true;
    openMulticastPort = true;
    settings = {
      # Basic peer discovery - customize with actual bootstrap peers
      Peers = [
        # Add bootstrap peers here for initial connectivity
        # Examples:
        # "tcp://ygg-boot.example.com:8080"
        # "tls://[2001:db8::1]:443"
      ];

      # Enable local multicast discovery
      MulticastInterfaces = [
        {
          Regex = ".*";
          Beacon = true;
          Listen = true;
        }
      ];

      # Optional: Configure allowed encryption keys for private peering
      # AllowedEncryptionPublicKeys = [];

      # Optional: Enable node info sharing
      NodeInfo = {
        name = config.networking.hostName;
        location = "residential";
      };
    };
  };

  # Open firewall for Yggdrasil
  networking.firewall = {
    allowedUDPPorts = [
      9001  # Yggdrasil default port
    ];
    # Allow Yggdrasil to bind to any available port for outgoing connections
    allowedTCPPortRanges = [
      { from = 32768; to = 65535; }  # Ephemeral port range
    ];
  };

  # Ensure Yggdrasil interface is managed properly
  systemd.network.networks."50-yggdrasil" = {
    matchConfig.Name = "tun0";
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
    };
    linkConfig.RequiredForOnline = false;
  };
}