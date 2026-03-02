# netbird.nix — system-manager module for Netbird WireGuard mesh client.
#
# /etc/netbird/netbird.env (NETBIRD_MANAGEMENT_URL, NETBIRD_SETUP_KEY) is
# written by the Ansible netbird role (sensitive; stays out of the Nix closure).
# One-time mesh enrollment (netbird up) is also performed by Ansible.
{ pkgs, ... }:
{
  # Make the netbird CLI available system-wide for Ansible enrollment tasks.
  # Binary is accessible at /run/system-manager/sw/bin/netbird after activation.
  environment.systemPackages = [ pkgs.netbird ];

  systemd.services.netbird = {
    description = "Netbird WireGuard mesh client";
    documentation = [ "https://netbird.io/" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      # Optional env file: service starts even if not yet written by Ansible.
      # Restart after Ansible writes the file to pick up management URL.
      EnvironmentFile = "-/etc/netbird/netbird.env";
      ExecStart = "${pkgs.netbird}/bin/netbird service run";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
