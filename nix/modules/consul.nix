# consul.nix — parameterised system-manager module for Consul agent.
#
# Usage (in flake.nix):
#   import ./nix/modules/consul.nix {
#     datacenter = "home";
#     isServer = false;
#     retryJoin = [ "10.0.0.1" "10.0.0.2" ];
#   }
#
# bind_addr uses Consul's own Go-template expression evaluated at runtime,
# so no IP address is baked into the Nix closure.
{ datacenter
, isServer ? false
, bootstrapExpect ? 3
, retryJoin ? []
, retryJoinWan ? []
}:
{ pkgs, lib, ... }:
{
  environment.etc."consul/consul.hcl" = {
    text =
      ''
        # /etc/consul/consul.hcl — managed by system-manager (hyphae consul module)

        datacenter = "${datacenter}"
        data_dir   = "/var/lib/consul"

        # Bind to the Netbird WireGuard interface; evaluated at runtime by Consul.
        bind_addr   = {{ GetInterfaceIP "wt0" }}
        client_addr = "127.0.0.1"

        server = ${lib.boolToString isServer}
      ''
      + lib.optionalString isServer ''
        bootstrap_expect = ${toString bootstrapExpect}
      ''
      + lib.optionalString (retryJoin != []) (
        ''
          retry_join = [
        ''
        + lib.concatStringsSep "\n" (map (a: "  \"${a}\",") retryJoin)
        + ''

          ]
        ''
      )
      + lib.optionalString (retryJoinWan != []) (
        ''
          retry_join_wan = [
        ''
        + lib.concatStringsSep "\n" (map (a: "  \"${a}\",") retryJoinWan)
        + ''

          ]
        ''
      )
      + ''

        ports {
          dns  = 8600
          http = 8500
          grpc = 8502
        }

        recursors = ["1.1.1.1", "8.8.8.8"]
      '';
    mode = "0644";
  };

  systemd.services.consul = {
    description = "Consul cluster agent";
    documentation = [ "https://www.consul.io/" ];
    requires = [ "network-online.target" ];
    # sops-install-secrets is a soft ordering dep: consul waits for secrets if
    # the service exists, but does not fail if no secrets are declared for this node.
    after = [ "network-online.target" "sops-install-secrets.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "consul";
      Group = "consul";
      ExecStart = "${pkgs.consul}/bin/consul agent -config-file=/etc/consul/consul.hcl";
      ExecReload = "/bin/kill -HUP $MAINPID";
      KillMode = "process";
      Restart = "on-failure";
      RestartSec = 5;
      LimitNOFILE = 65536;
    };
  };
}
