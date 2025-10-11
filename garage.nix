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
      replication_mode = "2";  # 2 copies across nodes for 2-node setup

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

  # Create garage user, data directories, and secrets directories
  systemd.tmpfiles.rules = [
    "d /var/lib/garage 0755 garage garage -"
    "d /var/lib/garage/data 0755 garage garage -"
    "d /var/lib/garage/meta 0755 garage garage -"
    "d /etc/garage 0755 root root -"
    "d /etc/hyphae 0755 root root -"
    "d /etc/hyphae/secrets 0700 root root -"
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
}
