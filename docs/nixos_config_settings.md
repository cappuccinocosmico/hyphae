# NixOS Configuration Settings for Hyphae

This document covers the essential NixOS configuration settings discovered and implemented for the Hyphae distributed storage system.

## Overview

The Hyphae system uses two main NixOS services:
- **Yggdrasil**: Mesh networking for connecting nodes across residential networks
- **Garage**: S3-compatible distributed object storage

## Yggdrasil Configuration

### Key NixOS Options

Based on NixOS search results, the main `services.yggdrasil` options are:

- `services.yggdrasil.enable` - Enable the service
- `services.yggdrasil.package` - Which Yggdrasil package to use
- `services.yggdrasil.persistentKeys` - Keep keys across reboots
- `services.yggdrasil.configFile` - Custom config file path
- `services.yggdrasil.settings` - Main configuration block
- `services.yggdrasil.openMulticastPort` - Open firewall for multicast discovery
- `services.yggdrasil.denyDhcpcdInterfaces` - Prevent DHCP on Yggdrasil interfaces
- `services.yggdrasil.group` - Service group
- `services.yggdrasil.extraArgs` - Additional command-line arguments

### Essential Settings for Hyphae

```nix
services.yggdrasil = {
  enable = true;
  persistentKeys = true;  # Keep same identity across reboots
  openMulticastPort = true;  # Enable local peer discovery
  settings = {
    # Bootstrap peers for initial connectivity
    Peers = [
      # "tcp://ygg-boot.example.com:8080"
      # "tls://[2001:db8::1]:443"
    ];

    # Enable local network discovery
    MulticastInterfaces = [
      {
        Regex = ".*";  # All interfaces
        Beacon = true;  # Announce presence
        Listen = true;  # Listen for peers
      }
    ];

    # Optional node identification
    NodeInfo = {
      name = config.networking.hostName;
      location = "residential";
    };
  };
};
```

### Network Configuration

Yggdrasil creates a `tun0` interface that needs proper network management:

```nix
# Prevent systemd-networkd from interfering
systemd.network.networks."50-yggdrasil" = {
  matchConfig.Name = "tun0";
  networkConfig = {
    DHCP = "no";
    IPv6AcceptRA = false;
  };
  linkConfig.RequiredForOnline = false;
};

# Firewall configuration
networking.firewall = {
  allowedUDPPorts = [ 9001 ];  # Default Yggdrasil port
  allowedTCPPortRanges = [
    { from = 32768; to = 65535; }  # Ephemeral ports for outgoing connections
  ];
};
```

## Garage Configuration

### Key NixOS Options

From NixOS search, the main `services.garage` options are:

- `services.garage.enable` - Enable the service
- `services.garage.package` - Which Garage package to use
- `services.garage.settings` - Main configuration block
- `services.garage.settings.data_dir` - Data storage path
- `services.garage.settings.metadata_dir` - Metadata storage path
- `services.garage.logLevel` - Logging verbosity
- `services.garage.environmentFile` - File containing environment variables
- `services.garage.extraEnvironment` - Additional environment variables

### Essential Settings for 2-Node Cluster

```nix
services.garage = {
  enable = true;
  logLevel = "info";
  environmentFile = "/etc/garage/garage.env";  # For secrets

  settings = {
    # Storage paths
    data_dir = "/var/lib/garage/data";
    metadata_dir = "/var/lib/garage/meta";

    # Replication for 2-node setup
    replication_mode = "2";  # 2 copies across nodes

    # Inter-node communication over Yggdrasil
    rpc_bind_addr = "[::]:3901";
    rpc_public_addr = "[yggdrasil-ipv6]:3901";  # Set per-node

    # S3 API configuration
    s3_api = {
      s3_region = "hyphae";
      api_bind_addr = "[::]:3900";
      root_domain = ".s3.hyphae.local";
    };

    # Web admin interface
    admin = {
      api_bind_addr = "[::]:3903";
      admin_token = "set-via-environment-file";
    };
  };
};
```

### Security Configuration

**Automatic Secret Generation**: The Hyphae module automatically generates all required secrets on first startup, eliminating manual configuration:

- **RPC Secret**: Auto-generated and stored in `/etc/hyphae/secrets/garage_rpc_key`
- **Admin Token**: Auto-generated and stored in `/etc/hyphae/secrets/garage_admin_token`
- **Metrics Token**: Auto-generated and stored in `/etc/hyphae/secrets/garage_metrics_token`

Secrets are automatically:
- Generated using cryptographically secure random data (`openssl rand -base64 32`)
- Stored with 600 permissions (owner-readable only)
- Persistent across system rebuilds and reboots
- Used to create the environment file at startup

No manual secret management required - just deploy the module and it works!

### Directory Setup

```nix
systemd.tmpfiles.rules = [
  "d /var/lib/garage 0755 garage garage -"
  "d /var/lib/garage/data 0755 garage garage -"
  "d /var/lib/garage/meta 0755 garage garage -"
  "d /etc/garage 0755 root root -"
];
```

### Service Dependencies

Ensure Garage starts after Yggdrasil is ready:

```nix
systemd.services.garage = {
  after = [ "yggdrasil.service" ];
  wants = [ "yggdrasil.service" ];
};
```

## Deployment Strategy

### Flake Structure

```nix
{
  nixosConfigurations = {
    hyphae-node = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix  # Hardware-specific config
        ./yggdrasil.nix              # Yggdrasil mesh networking
        ./garage.nix                 # Garage storage
      ];
    };
  };
}
```

### Per-Node Customization

Each node needs unique settings:

1. **Yggdrasil IPv6 address** - Auto-generated, get with `yggdrasilctl getSelf`
2. **Garage RPC address** - Set to node's Yggdrasil IPv6
3. **Bootstrap peers** - At least one node needs connectivity to external peers
4. **Storage paths** - Customize for available disk space

### Port Requirements

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| Yggdrasil | 9001 | UDP | Mesh networking |
| Garage S3 | 3900 | TCP | S3 API |
| Garage RPC | 3901 | TCP | Inter-node communication |
| Garage Admin | 3903 | TCP | Web admin interface |

## Common Issues and Solutions

### Yggdrasil Connectivity

- **No peers found**: Add bootstrap peers to `Peers` array
- **Firewall blocking**: Ensure UDP 9001 is open
- **Interface conflicts**: Configure systemd-networkd to ignore `tun0`

### Garage Cluster Formation

- **Nodes can't communicate**: Check `rpc_public_addr` points to Yggdrasil IPv6
- **Authentication failed**: Verify `rpc_secret` matches across nodes
- **Storage permissions**: Ensure garage user can write to data directories

### 2-Node Limitations

- **No fault tolerance**: If one node goes down, cluster is read-only
- **Split-brain prevention**: Garage handles this automatically
- **Replication factor**: Must be set to 2 (not higher) for 2-node setup

## Security Considerations

1. **Use environment files** for all secrets (tokens, keys)
2. **Set proper file permissions** (0600 for secrets)
3. **Consider RPC secrets** for cluster authentication
4. **Firewall rules** should be minimal and specific
5. **Regular key rotation** for admin/metrics tokens

## Testing and Validation

### Check Yggdrasil Status
```bash
sudo yggdrasilctl getSelf
sudo yggdrasilctl getPeers
```

### Check Garage Status
```bash
garage status
garage layout show
```

### Verify Connectivity
```bash
# From one node, test connection to other node's Garage
curl -v http://[other-node-yggdrasil-ipv6]:3900/
```