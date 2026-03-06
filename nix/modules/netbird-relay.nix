# netbird-relay.nix — NixOS module for the Netbird relay server.
#
# No upstream module exists in nixpkgs yet (PR #354032 open).
# The relay is a standalone binary that proxies traffic between peers behind
# symmetric NAT.  All configuration is via environment variables.
#
# This module expects nginx to terminate TLS and proxy WebSocket connections
# to the internal listen address.  The exposed address should therefore use
# the rels:// scheme pointing at the public nginx port.
#
# Required secret:  NB_AUTH_SECRET  (read from authSecretFile via LoadCredential)
{ config, lib, pkgs, ... }:

let
  cfg = config.services.netbird-relay;
  pkg = cfg.package;
in
{
  options.services.netbird-relay = {
    enable = lib.mkEnableOption "Netbird relay server";

    package = lib.mkPackageOption pkgs "netbird-relay" { };

    # Internal address the relay process binds to (behind nginx).
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:33081";
      description = "Internal listen address (host:port).  Nginx proxies the public port to this.";
    };

    # Public address advertised to Netbird peers.
    # Must match what peers will actually connect to (nginx public TLS port).
    exposedAddress = lib.mkOption {
      type = lib.types.str;
      example = "rels://netbird.example.com:33080";
      description = "Public relay address including scheme (rels:// for TLS, rel:// for plain).";
    };

    # Path to a file whose entire content is the relay auth secret.
    # Typically a sops-nix managed secret path.
    authSecretFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to a file containing the relay NB_AUTH_SECRET value.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ "ERROR" "WARN" "INFO" "DEBUG" "TRACE" ];
      default = "INFO";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.netbird-relay = {
      description = "Netbird relay server";
      documentation = [ "https://docs.netbird.io/selfhosted/relay" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        # Load auth secret via systemd credential store (mode 0400, root-only).
        LoadCredential = [ "auth-secret:${cfg.authSecretFile}" ];

        ExecStart = lib.escapeShellArgs [
          (lib.getExe' pkg "netbird-relay")
        ];

        # Inject the secret from $CREDENTIALS_DIRECTORY into the environment.
        ExecStartPre = pkgs.writeShellScript "netbird-relay-env" ''
          echo "NB_AUTH_SECRET=$(cat "$CREDENTIALS_DIRECTORY/auth-secret")" \
            >> /run/netbird-relay/env
        '';
        EnvironmentFile = "/run/netbird-relay/env";

        Environment = [
          "NB_LISTEN_ADDRESS=${cfg.listenAddress}"
          "NB_EXPOSED_ADDRESS=${cfg.exposedAddress}"
          "NB_LOG_LEVEL=${cfg.logLevel}"
          "NB_LOG_FORMAT=json"
        ];

        RuntimeDirectory = "netbird-relay";
        RuntimeDirectoryMode = "0700";

        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
      };
    };
  };
}
