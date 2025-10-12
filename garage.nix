{ config, lib, pkgs, ... }:

{
  # Enable Garage distributed storage
  services.garage = {
    enable = true;
    package = pkgs.garage;
    logLevel = "info";
    settings = {
      # Data storage paths - customize per node
      data_dir = "/var/lib/garage/data";
      metadata_dir = "/var/lib/garage/meta";

      # Cluster configuration
      replication_mode = "1"; 

      # RPC configuration for inter-node communication
      # Bind to all interfaces, will be accessible via Yggdrasil
      rpc_bind_addr = "[::]:3901";

      # This should be set to the node's Yggdrasil IPv6 address
      # For now using placeholder - should be configured per-node
      rpc_public_addr = "[::1]:3901";

      # Optional: Configure RPC secret for cluster security
      # rpc_secret_file = "/etc/garage/rpc-secret";

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
        # Admin token should be set via environment file for security
        admin_token = "change-this-admin-token";

        # Optional: Metrics endpoint
        metrics_token = "change-this-metrics-token";
      };

      # K2V API (optional, for key-value storage)
      # k2v_api = {
      #   api_bind_addr = "[::]:3902";
      # };
    };

    # Use environment file for sensitive configuration
    environmentFile = "/etc/hyphae/secrets/garage.env";
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
    "d /var/lib/garage 0755 garage garage -"
    "d /var/lib/garage/data 0755 garage garage -"
    "d /var/lib/garage/meta 0755 garage garage -"
    "d /etc/garage 0755 root root -"
    "d /etc/hyphae 0755 root root -"
    "d /etc/hyphae/secrets 0700 root root -"
    "d /etc/hyphae/mounts 0755 root root -"
    "d /etc/hyphae/mounts/hyphae-data 0755 root root -"
  ];

  # Generate secrets during system activation
  system.activationScripts.hyphae-secrets = {
    text = ''
      # Ensure secrets directory exists
      mkdir -p /etc/hyphae/secrets

      # Generate the environment file with all secrets if it doesn't exist
      if [[ ! -f /etc/hyphae/secrets/garage.env ]]; then
        echo "Generating garage environment file with new secrets..."
        cat > /etc/hyphae/secrets/garage.env << EOF
# Garage Environment Configuration - Auto-generated secrets
GARAGE_RPC_SECRET=$(${pkgs.openssl}/bin/openssl rand -hex 32)
GARAGE_ADMIN_TOKEN=$(${pkgs.openssl}/bin/openssl rand -base64 32)
GARAGE_METRICS_TOKEN=$(${pkgs.openssl}/bin/openssl rand -base64 32)
EOF
        chmod 600 /etc/hyphae/secrets/garage.env
        echo "Garage secrets generated successfully"
      else
        echo "Garage environment file already exists, using existing secrets"
      fi
    '';
    deps = [ ];
  };

  # Configure garage service dependencies
  systemd.services.garage = {
    after = [ "yggdrasil.service" ];
    wants = [ "yggdrasil.service" ];
  };

  # Add s3fs package for mounting S3 buckets
  environment.systemPackages = [ pkgs.s3fs ];

  # Generate S3 credentials for mounting
  system.activationScripts.hyphae-s3-credentials = {
    text = ''
      # Create S3 credentials file for s3fs if it doesn't exist
      if [[ ! -f /etc/hyphae/secrets/s3-credentials ]]; then
        echo "Generating S3 credentials for bucket mounting..."
        cat > /etc/hyphae/secrets/s3-credentials << EOF
# S3 credentials for hyphae-data bucket mounting
# Default access key and secret for Garage
hyphae-access-key:hyphae-secret-key
EOF
        chmod 600 /etc/hyphae/secrets/s3-credentials
        echo "S3 credentials file created (you'll need to update with actual keys after bucket setup)"
      fi
    '';
    deps = [ "hyphae-secrets" ];
  };

  # Mount hyphae-data S3 bucket using s3fs
  fileSystems."/etc/hyphae/mounts/hyphae-data" = {
    device = "hyphae-data";
    fsType = "fuse.s3fs";
    options = [
      "passwd_file=/etc/hyphae/secrets/s3-credentials"
      "url=http://localhost:3900"  # Garage S3 API endpoint
      "use_path_request_style"     # Required for Garage compatibility
      "allow_other"                # Allow other users to access
      "uid=0"                      # Mount as root
      "gid=0"                      # Mount as root group
      "umask=022"                  # Readable by all, writable by owner
      "nonempty"                   # Allow mounting on non-empty directory
      "_netdev"                    # Wait for network
    ];
    # Only mount after garage service is running
    depends = [ "garage.service" ];
  };
}
