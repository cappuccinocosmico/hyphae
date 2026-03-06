# configuration.nix — NixOS config for vps1 (IONOS VPS).
#
# Roles:
#   • Netbird management + signal + coturn server  → peers reach each other
#   • Netbird relay server (custom module)          → symmetric-NAT traversal
#   • Consul + Nomad client                         → participates in cluster
#
# Secret files injected by nixos-anywhere --extra-files (plain files, mode 0400):
#
#   /etc/age/cluster.key                    ← shared cluster age private key
#                                             (from provisioning.secrets.yaml)
#   /etc/hyphae/device-secrets/
#     netbird-store-key                     ← AES-256 key for mgmt SQLite store
#     coturn-password                       ← TURN user password (lt-cred-mech)
#     coturn-turn-secret                    ← HMAC secret for time-based creds
#     netbird-relay-secret                  ← relay auth secret
#
# Device secrets live only on this node; inspect via SSH if needed.
# They are never in the repo.  Cluster secrets (consul/nomad gossip keys etc.)
# come from secrets/cluster.secrets.yaml, decrypted at runtime by sops-nix
# using the cluster age key.
#
# Deploy with:
#   # Build extras directory (see README for full commands)
#   nixos-anywhere --flake .#vps1 --extra-files /tmp/vps1-extras root@<IP>
{ config, lib, pkgs, ... }:

let
  # Shorthand so service configs stay readable.
  ds = "/etc/hyphae/device-secrets";
in
{
  # ── System ────────────────────────────────────────────────────────────────
  system.stateVersion = "24.11";
  networking.hostName = "vps1";
  time.timeZone = "UTC";

  # ── Boot ──────────────────────────────────────────────────────────────────
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev"; # disko sets the actual device
  };
  boot.loader.efi.canTouchEfiVariables = false;

  # ── Networking ────────────────────────────────────────────────────────────
  networking.useDHCP = lib.mkDefault true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      80    # ACME HTTP-01 challenges
      443   # HTTPS (management + signal via nginx)
      33080 # Netbird relay (nginx TLS proxy → internal 33081)
    ];
    # coturn STUN/TURN ports and relay range opened automatically by the coturn module
  };

  # ── SSH ───────────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # ── User ──────────────────────────────────────────────────────────────────
  # TODO: add your SSH public key before deploying.
  users.users.root.openssh.authorizedKeys.keys = [
    # "ssh-ed25519 AAAA... you@host"
  ];
  users.users.nicole = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... you@host"
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  # ── Secrets (sops-nix — cluster-wide only) ────────────────────────────────
  # The shared cluster age key is injected by nixos-anywhere at deploy time.
  # sops-nix uses it to decrypt cluster.secrets.yaml at boot for cluster-wide
  # runtime secrets (consul/nomad gossip keys etc., added as the cluster grows).
  # Device-specific secrets (coturn, relay, mgmt store key) are plain files
  # under /etc/hyphae/device-secrets/ — also injected by nixos-anywhere.
  sops.age.keyFile = "/etc/age/cluster.key";
  sops.defaultSopsFile = ../../../secrets/cluster.secrets.yaml;
  # sops.secrets are declared here as cluster secrets are added to cluster.secrets.yaml.

  # ── Netbird management + signal + coturn ──────────────────────────────────
  services.netbird.server = {
    enable = true;
    domain = "netbird.mycor.io";
    enableNginx = true;

    # Dashboard requires an OIDC provider for user login; disabled until a
    # future phase adds an IdP (Zitadel/Authentik).
    dashboard.enable = false;

    management = {
      # No external IdP; IdpManagerConfig.ManagerType defaults to "none".
      # Nodes enroll via setup keys only.
      # Initial API token appears in the management server logs on first start:
      #   journalctl -u netbird-management | grep -i token
      oidcConfigEndpoint = "";

      singleAccountModeDomain = "mycor.io";
      disableAnonymousMetrics = true;

      settings = {
        # Plain device-secret files; the `_secret` value is read at service
        # start by genJqSecretsReplacementSnippet and spliced into the JSON.
        DataStoreEncryptionKey = { _secret = "${ds}/netbird-store-key"; };
        TURNConfig.Secret      = { _secret = "${ds}/coturn-turn-secret"; };
        # TURNConfig.Turns password flows automatically from coturn.passwordFile.
      };
    };

    coturn = {
      enable = true;
      domain = "netbird.mycor.io";
      passwordFile = "${ds}/coturn-password";
    };
  };

  # Limit TURN relay port range for a small home-lab cluster.
  services.coturn.min-port = 49152;
  services.coturn.max-port = 49300;

  # ── Netbird relay ─────────────────────────────────────────────────────────
  services.netbird-relay = {
    enable = true;
    listenAddress = "127.0.0.1:33081";
    exposedAddress = "rels://netbird.mycor.io:33080";
    authSecretFile = "${ds}/netbird-relay-secret";
  };

  # ── Nginx + ACME ──────────────────────────────────────────────────────────
  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedProxySettings = true;
    recommendedGzipSettings = true;

    # Add ACME/TLS to the vhost that services.netbird.server.enableNginx creates.
    virtualHosts."netbird.mycor.io" = {
      enableACME = true;
      forceSSL = true;
    };

    # Relay on port 33080, TLS-terminated by nginx, proxying to internal relay.
    virtualHosts."netbird-relay" = {
      serverName = "netbird.mycor.io";
      listen = [ { addr = "0.0.0.0"; port = 33080; ssl = true; } ];
      useACMEHost = "netbird.mycor.io";
      locations."/" = {
        proxyPass = "http://127.0.0.1:33081";
        extraConfig = ''
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          proxy_read_timeout 1d;
          proxy_send_timeout 1d;
        '';
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@mycor.io"; # TODO: replace with real address
  };

  # ── Nix ───────────────────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" "nicole" ];

  environment.systemPackages = with pkgs; [ netbird age sops git htop jq ];
}
