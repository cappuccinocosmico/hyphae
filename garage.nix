{ config, lib, pkgs, ... }:

let
  hyphaeLib = import ./lib.nix { inherit lib pkgs; };
in
{
  # Configure sops-nix for secrets management
  sops.defaultSopsFile = ./secrets/secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # Create hyphae group for shared access to secrets
  users.groups.hyphae = {};

  # Define secrets with proper permissions for hyphae services
  sops.secrets.garage-rpc-secret = {
    mode = "0440";
    group = "hyphae";
  };
  sops.secrets.garage-admin-token = {
    mode = "0440";
    group = "hyphae";
  };
  sops.secrets.garage-metrics-token = {
    mode = "0440";
    group = "hyphae";
  };
  sops.secrets.s3-access-key-id = {};
  sops.secrets.s3-secret-key = {};
  # Enable Garage distributed storage
  services.garage = {
    enable = true;
    package = pkgs.garage;
    logLevel = "info";
    settings = {
      # Data storage paths - persistent across NixOS rebuilds
      data_dir = "/etc/hyphae/persistent/garage/data";
      metadata_dir = "/etc/hyphae/persistent/garage/meta";

      # Cluster configuration
      replication_mode = "1"; 

      # RPC configuration for inter-node communication
      # Bind to all interfaces, will be accessible via Yggdrasil
      rpc_bind_addr = "[::]:3901";

      # This should be set to the node's Yggdrasil IPv6 address
      # For now using placeholder - should be configured per-node
      rpc_public_addr = "[::1]:3901";

      # RPC secret for cluster security (managed by sops-nix)
      rpc_secret_file = config.sops.secrets.garage-rpc-secret.path;

      # S3 API configuration
      s3_api = {
        s3_region = "hyphae";
        api_bind_addr = "[::]:3900";
        root_domain = ".s3.hyphae.local";

        # Optional: Enable virtual-hosted-style requests
        # api_bind_addr_https = "[::]:3443";
      };

      # Web admin interface
      admin = {
        api_bind_addr = "[::]:3903";
        # Admin and metrics tokens (managed by sops-nix)
        admin_token_file = config.sops.secrets.garage-admin-token.path;
        metrics_token_file = config.sops.secrets.garage-metrics-token.path;
      };

      # K2V API (optional, for key-value storage)
      # k2v_api = {
      #   api_bind_addr = "[::]:3902";
      # };
    };

    # Secrets are now managed by sops-nix, no environment file needed
  };

  # Open firewall ports for Garage services
  networking.firewall = {
    allowedTCPPorts = [
      3900  # Garage S3 API
      3901  # Garage RPC (inter-node communication)
      3903  # Garage admin interface
      # 3902  # K2V API (if enabled)
    ];
  };

  # Create garage user, data directories, secrets directories, and mount points
  systemd.tmpfiles.rules = [
    "d /etc/garage 0755 root root -"
    "d /etc/hyphae 0755 root root -"
    "d /etc/hyphae/persistent 0755 root root -"
    "d /etc/hyphae/persistent/garage 0755 garage garage -"
    "d /etc/hyphae/persistent/garage/data 0755 garage garage -"
    "d /etc/hyphae/persistent/garage/meta 0755 garage garage -"
    "d /etc/hyphae/secrets 0700 root root -"
    "d /etc/hyphae/mounts 0755 root root -"
    "d /etc/hyphae/mounts/hyphae-data 0755 root root -"
  ];

  # Create S3 credentials file using sops-nix templates (for s3fs compatibility)
  sops.templates."s3-credentials".content = ''
    ${config.sops.placeholder."s3-access-key-id"}:${config.sops.placeholder."s3-secret-key"}
  '';
  sops.templates."s3-credentials".mode = "0600";
  sops.templates."s3-credentials".path = "/etc/hyphae/secrets/s3-credentials";

  # Create rclone configuration file using sops-nix templates
  sops.templates."rclone.conf".content = ''
    [garage]
    type = s3
    provider = Other
    access_key_id = ${config.sops.placeholder."s3-access-key-id"}
    secret_access_key = ${config.sops.placeholder."s3-secret-key"}
    endpoint = http://localhost:3900
    region = hyphae
    acl = private
    force_path_style = true
  '';
  sops.templates."rclone.conf".mode = "0600";
  sops.templates."rclone.conf".path = "/etc/hyphae/secrets/rclone.conf";

  # Configure garage service dependencies and group membership
  systemd.services.garage = {
    after = [ "yggdrasil.service" ];
    wants = [ "yggdrasil.service" ];
    serviceConfig = {
      SupplementaryGroups = [ "hyphae" ];
    };
    environment = {
      GARAGE_ALLOW_WORLD_READABLE_SECRETS = "true";
    };
  };

  # Add rclone package for mounting S3 buckets
  environment.systemPackages = [ pkgs.rclone ];


  # Mount hyphae-data S3 bucket using rclone
  fileSystems."/etc/hyphae/mounts/hyphae-data" = {
    device = "garage:hyphae-data";
    fsType = "rclone";
    options = hyphaeLib.defaultHyphaeRcloneMountOptions;
    depends = [ "garage.service" ];
  };
}
