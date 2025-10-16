{ config, lib, pkgs, ... }:

let
  hyphaeLib = import ./lib.nix { inherit lib pkgs; };
in
{
  # Configure sops-nix for kavita token
  sops.defaultSopsFile = ./secrets/secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];


  # Define kavita secret with hyphae group access
  sops.secrets.kavita-token = {
    mode = "0440";
    group = "hyphae";
  };
  # Enable Kavita digital library service
  services.kavita = {
    enable = true;
    user = "kavita";
    dataDir = "/var/lib/kavita";
    settings = {
      Port = 5000;
      IpAddresses = "::"; # Bind to all interfaces for Yggdrasil access
    };
    tokenKeyFile = config.sops.secrets.kavita-token.path;
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

    # Ensure kavita can access the mounted books directory and hyphae secrets
    serviceConfig = {
      BindPaths = [ "/etc/hyphae/mounts/hyphae-books:/var/lib/kavita/books" ];
      SupplementaryGroups = [ "hyphae" ];
    };
  };
}