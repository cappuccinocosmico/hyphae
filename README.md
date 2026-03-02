# Hyphae

A self-hosted distributed document storage cluster. Nodes run Consul (service
mesh), Nomad (workload orchestration), and Netbird (WireGuard overlay) — all
pinned via this Nix flake and managed by systemd.

## Architecture

- **Overlay network**: Netbird WireGuard mesh; all cluster traffic stays on `wt0`
- **Service discovery**: Consul agents on every node; Consul Go-template resolves bind addresses at runtime so no IPs are baked into config
- **Workload scheduling**: Nomad with `raw_exec` driver; `raw_exec` jobs run as root children of the agent
- **Secrets**: sops-encrypted `secrets/secrets.yaml`; decrypted to `/run/secrets/` on boot by `hyphae-secrets.service`
- **Config management**: `nix/modules/` contains all service definitions as standard NixOS modules

## Node types

| Group | `nodeRole` | `consul_datacenter` | Notes |
|-------|-----------|---------------------|-------|
| `storage` | `storage` | `home` | `hasStorage = true` |
| `vps` | `vps` | `cloud` | |
| `light` | `edge` | `home` | |
| `gpu` | `edge` | `home` | `hasGpu = true` |

---

## Deploying a non-NixOS node (Ubuntu, Debian, …)

Services are defined in `nix/modules/` and activated via
[system-manager](https://github.com/numtide/system-manager). Ansible handles
only what Nix can't: creating system users and the one-time `netbird up`
enrollment.

### 1. Prerequisites

```sh
# On your operator machine
nix develop   # enters devShell with ansible, nomad, consul, netbird, sops, age
```

### 2. Inventory

Edit `ansible/inventory/hosts.ini` and add the node under the correct group.
**The hostname must exactly match a key in `flake.nix` `systemConfigs`.**
If you're adding a new node, add a `mkNode` entry in `flake.nix` first.

```ini
[storage]
storage1 ansible_host=192.168.1.10
```

### 3. Vault secrets

Create or update `ansible/inventory/group_vars/all.yml` (or host_vars) with:

```sh
ansible-vault edit ansible/inventory/group_vars/all.yml
# set: hyphae_age_key, netbird_setup_key
```

### 4. Bootstrap

```sh
ansible-playbook ansible/bootstrap.yml -l storage1 --ask-vault-pass
```

This runs four roles in order:

| Role | What it does |
|------|-------------|
| `common` | Creates system users (`consul`, `nomad`, …); loads fuse kernel module |
| `nix` | Installs Nix (Determinate Systems); syncs repo to `/opt/hyphae`; runs `system-manager switch` |
| `hyphae-secrets` | Writes `/etc/hyphae/age.key` + `secrets.yaml`; restarts `hyphae-secrets.service` to decrypt |
| `netbird` | Writes `/etc/netbird/netbird.env`; restarts `netbird.service`; runs `netbird up` to enroll |

### 5. Verify

```sh
systemctl status hyphae-secrets consul nomad netbird
ls /run/secrets/
nomad node status && consul members && netbird status
```

---

## Deploying a NixOS node

The `nix/modules/` files are standard NixOS modules, so NixOS nodes skip
Ansible entirely (except for the one-time `netbird up` enrollment if desired).

### 1. Add a nixosConfigurations entry

In `flake.nix`, uncomment and fill in the `nixosConfigurations` block:

```nix
nixosConfigurations = {
  storage1 = mkNixosNode {
    nodeRole = "storage";
    consulDatacenter = "home";
    hasStorage = true;
    extraModules = [
      ./hosts/storage1/hardware-configuration.nix
      # any other host-specific NixOS options
    ];
  };
};
```

`mkNixosNode` adds the same service modules as `mkNode` and also declares
`consul` and `nomad` system users declaratively (no Ansible `common` role needed).

### 2. Write the age key

The secrets service still needs `/etc/hyphae/age.key` on the node. On NixOS
you can manage this with [agenix](https://github.com/ryantm/agenix) or
[sops-nix](https://github.com/Mic92/sops-nix), or write it manually once:

```sh
# one-time, on the node
install -m 600 /dev/stdin /etc/hyphae/age.key <<< "$AGE_PRIVATE_KEY"
```

### 3. Deploy

```sh
nixos-rebuild switch --flake .#storage1
```

### 4. Enroll into Netbird

After the first rebuild, write the netbird env file and enroll:

```sh
# on the node
install -d -m 700 /etc/netbird
printf 'NETBIRD_MANAGEMENT_URL=%s\nNETBIRD_SETUP_KEY=%s\n' \
  "$NETBIRD_URL" "$NETBIRD_KEY" > /etc/netbird/netbird.env
chmod 600 /etc/netbird/netbird.env
systemctl restart netbird
netbird up --management-url "$NETBIRD_URL" --setup-key "$NETBIRD_KEY"
```

---

## Day-2 operations

```sh
# Re-deploy config changes to a non-NixOS node
ansible-playbook ansible/bootstrap.yml -l <hostname> --ask-vault-pass

# Re-deploy config changes to a NixOS node
nixos-rebuild switch --flake .#<hostname>

# Rotate secrets (re-encrypt secrets.yaml, then push to nodes)
sops secrets/secrets.yaml
ansible-playbook ansible/bootstrap.yml -l all --ask-vault-pass --tags hyphae-secrets
```
