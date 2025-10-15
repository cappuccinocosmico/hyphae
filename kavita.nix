{ config, lib, pkgs, ... }:

let
  hyphaeLib = import ./lib.nix { inherit lib pkgs; };
in
{
  # Enable Kavita digital library service
  services.kavita = {
    enable = true;
    user = "kavita";
    dataDir = "/var/lib/kavita";
    settings = {
      Port = 5000;
      IpAddresses = "::"; # Bind to all interfaces for Yggdrasil access
    };
    tokenKeyFile = "/etc/hyphae/secrets/kavita-token";
  };

  # Open firewall for Kavita web interface
  networking.firewall = {
    allowedTCPPorts = [
      5000  # Kavita web interface
    ];
  };

  # Create necessary directories for Kavita and book storage
  systemd.tmpfiles.rules = [
    "d /var/lib/kavita 0755 kavita kavita -"
    "d /etc/hyphae/mounts/hyphae-books 0755 root root -"
  ];

  # Generate Kavita token during system activation
  system.activationScripts.hyphae-kavita-token = {
    text = ''
      # Generate Kavita JWT token if it doesn't exist
      if [[ ! -f /etc/hyphae/secrets/kavita-token ]]; then
        echo "Generating Kavita JWT token..."
        ${pkgs.openssl}/bin/openssl rand -base64 64 > /etc/hyphae/secrets/kavita-token
        chmod 600 /etc/hyphae/secrets/kavita-token
        echo "Kavita token generated successfully"
      fi
    '';
    deps = [ "hyphae-secrets" ];
  };

  # Mount hyphae-books S3 bucket for Kavita library storage
  fileSystems."/etc/hyphae/mounts/hyphae-books" = {
    device = "hyphae-books";
    fsType = "fuse./run/current-system/sw/bin/s3fs";
    options = hyphaeLib.defaultHyphaeMountOptions;
    depends = [ "garage.service" ];
  };

  # Configure Kavita service dependencies
  systemd.services.kavita = {
    after = [ "garage.service" "etc-hyphae-mounts-hyphae\\x2dbooks.mount" ];
    wants = [ "garage.service" "etc-hyphae-mounts-hyphae\\x2dbooks.mount" ];

    # Ensure kavita can access the mounted books directory
    serviceConfig = {
      BindPaths = [ "/etc/hyphae/mounts/hyphae-books:/var/lib/kavita/books" ];
    };
  };
}