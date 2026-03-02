# nomad.nix — parameterised system-manager module for Nomad agent.
#
# Usage (in flake.nix):
#   import ./nix/modules/nomad.nix {
#     nodeRole = "storage";
#     hasStorage = true;
#   }
#
# Nomad runs as root so raw_exec tasks can be managed as child processes.
# network_interface binds to the Netbird WireGuard interface (wt0) at runtime.
{ nodeRole
, hasStorage ? false
, hasGpu ? false
, isServer ? false
, bootstrapExpect ? 3
}:
{ pkgs, lib, ... }:
{
  environment.etc."nomad/client.hcl" = {
    text =
      ''
        # /etc/nomad/client.hcl — managed by system-manager (hyphae nomad module)

        data_dir  = "/var/lib/nomad"
        log_level = "INFO"

        # Bind Nomad cluster traffic to the Netbird WireGuard interface.
        network_interface = "wt0"

        client {
          enabled = true

          # Capability metadata for constraint-based job placement.
          meta {
            "has_storage" = "${lib.boolToString hasStorage}"
            "has_gpu"     = "${lib.boolToString hasGpu}"
            "role"        = "${nodeRole}"
          }
        }

        consul {
          address = "127.0.0.1:8500"
        }

      ''
      + lib.optionalString isServer ''
        server {
          enabled          = true
          bootstrap_expect = ${toString bootstrapExpect}
        }

      ''
      + ''
        # raw_exec: run Nomad jobs as native processes (no container runtime needed).
        plugin "raw_exec" {
          config {
            enabled = true
          }
        }
      '';
    mode = "0644";
  };

  systemd.services.nomad = {
    description = "Nomad cluster agent";
    documentation = [ "https://www.nomadproject.io/" ];
    requires = [ "network-online.target" "hyphae-secrets.service" "consul.service" ];
    after = [ "network-online.target" "hyphae-secrets.service" "consul.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      # Root is required: Nomad manages raw_exec child processes and chowns task dirs.
      ExecStart = "${pkgs.nomad}/bin/nomad agent -config=/etc/nomad/client.hcl";
      ExecReload = "/bin/kill -HUP $MAINPID";
      KillMode = "process";
      Restart = "on-failure";
      RestartSec = 5;
      LimitNOFILE = 65536;
      TasksMax = "infinity";
    };
  };
}
