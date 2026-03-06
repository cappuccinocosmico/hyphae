# sops.nix — system-manager compatible secrets module.
#
# Mirrors the interface of sops-nix.nixosModules.sops so that secret
# declarations look identical on NixOS nodes (vps1) and system-manager nodes.
# Generates the sops-install-secrets manifest from Nix and runs the binary as
# a oneshot systemd service before consul and nomad start.
#
# On NixOS nodes, import sops-nix.nixosModules.sops directly instead of this
# file — it is richer and handles NixOS activation natively.
{ lib, pkgs, config, ... }:
let
  cfg = config.sops;

  secretsList = lib.mapAttrsToList (name: s: {
    inherit name;
    key          = s.key;
    path         = s.path;
    owner        = s.owner;
    uid          = 0;
    group        = s.group;
    gid          = 0;
    sopsFile     = if s.sopsFile != null then s.sopsFile else cfg.defaultSopsFile;
    format       = s.format;
    mode         = s.mode;
    restartUnits = s.restartUnits;
    reloadUnits  = s.reloadUnits;
  }) cfg.secrets;

  # Manifest is a Nix store path — static JSON with embedded runtime file paths.
  # sops-install-secrets reads this at activation time.
  manifest = pkgs.writeText "sops-manifest.json" (builtins.toJSON {
    secrets                 = secretsList;
    templates               = [];
    placeholderBySecretName = {};
    secretsMountPoint       = "/run/secrets.d";
    symlinkPath             = "/run/secrets";
    keepGenerations         = 1;
    sshKeyPaths             = [];
    gnupgHome               = "";
    ageKeyFile              = cfg.age.keyFile;
    ageSshKeyPaths          = [];
    useTmpfs                = true;
    userMode                = false;
    logging                 = { keyImport = false; secretChanges = true; };
  });
in
{
  options.sops = {
    defaultSopsFile = lib.mkOption {
      type        = lib.types.str;
      default     = "/etc/hyphae/secrets.yaml";
      description = ''
        Default SOPS-encrypted file from which secrets are decrypted.
        Can be overridden per secret via sops.secrets.<name>.sopsFile.
      '';
    };

    age.keyFile = lib.mkOption {
      type        = lib.types.str;
      default     = "/etc/hyphae/age.key";
      description = "Path to the age private key used to decrypt SOPS files.";
    };

    secrets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          key = lib.mkOption {
            type        = lib.types.str;
            default     = name;
            description = ''
              Key path within the SOPS file. Use dots for nested YAML
              (e.g. "cloudflare.API_TOKEN"). Defaults to the attribute name.
            '';
          };
          path = lib.mkOption {
            type        = lib.types.str;
            default     = "/run/secrets/${name}";
            description = "Destination path on disk. Defaults to /run/secrets/<name>.";
          };
          sopsFile = lib.mkOption {
            type        = lib.types.nullOr lib.types.str;
            default     = null;
            description = "SOPS file for this secret. Null uses sops.defaultSopsFile.";
          };
          format = lib.mkOption {
            type        = lib.types.str;
            default     = "yaml";
            description = "SOPS file format: yaml, json, binary, dotenv, or ini.";
          };
          mode = lib.mkOption {
            type        = lib.types.str;
            default     = "0400";
            description = "File mode for the decrypted secret.";
          };
          owner = lib.mkOption {
            type        = lib.types.nullOr lib.types.str;
            default     = null;
            description = "Owning user for the decrypted secret file.";
          };
          group = lib.mkOption {
            type        = lib.types.nullOr lib.types.str;
            default     = null;
            description = "Owning group for the decrypted secret file.";
          };
          restartUnits = lib.mkOption {
            type        = lib.types.listOf lib.types.str;
            default     = [];
            description = "Systemd units to restart when this secret changes.";
          };
          reloadUnits = lib.mkOption {
            type        = lib.types.listOf lib.types.str;
            default     = [];
            description = "Systemd units to reload when this secret changes.";
          };
        };
      }));
      default     = {};
      description = "Secrets to decrypt from SOPS files into /run/secrets.";
    };
  };

  config = lib.mkIf (cfg.secrets != {}) {
    # Make sops-install-secrets available on PATH after activation.
    environment.systemPackages = [ pkgs.sops-install-secrets ];

    systemd.services.sops-install-secrets = {
      description = "Decrypt SOPS secrets to /run/secrets";
      # Soft ordering: run before any service that may consume secrets.
      # No hard Requires= so nodes without secrets don't block on this unit.
      before   = [ "consul.service" "nomad.service" ];
      after    = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
        ExecStart       = "${pkgs.sops-install-secrets}/bin/sops-install-secrets ${manifest}";
      };
    };
  };
}
