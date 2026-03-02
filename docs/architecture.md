# Hyphae Architecture

Hyphae is a self-hosted distributed homelab platform deployable on any Linux machine.
It provides distributed media serving, ebook hosting, git + CI/CD, distributed LLM
inference, edge serverless compute, and internal DNS — all connected via an encrypted
WireGuard mesh and backed by distributed object storage.

---

## Design Principles

- **Cross-distro**: deployable on any systemd Linux; no NixOS or distro-specific tooling
- **Capability-driven placement**: node hardware determines which services run, not manual config
- **No single point of failure for data**: Garage replication factor = number of storage nodes
- **Minimal cloud dependency**: one public VPS as network anchor; all services self-hosted
- **Encrypted by default**: all inter-node traffic over WireGuard (Netbird); secrets via SOPS+age
- **No unnecessary containerisation**: services run as native processes via Nomad `raw_exec`;
  Docker is only used where sandboxing is a genuine requirement (CI runners)

---

## Node Taxonomy

| Role | Count | Requirements | Key services |
|------|-------|--------------|--------------|
| **VPS** | 1 | Public IPv4, always-on | Netbird servers, Caddy, Nomad server, Consul server |
| **Storage** | 2+ | Multi-TB drives, capable CPU | Garage, geesefs, Jellyfin, Kavita |
| **Light** | 4-6 | Any Linux + network | Edge workers, Nomad/Consul servers, CoreDNS |
| **GPU** | 0-N | NVIDIA/AMD GPU | Ollama |

Light nodes (cheap VPS, Raspberry Pi, spare hardware) carry the coordination infrastructure
deliberately. Storage nodes are the most likely to fail; keeping Nomad and Consul servers
on separate, stable nodes means the cluster survives a storage node going down.

---

## Topology

```
                          Internet
                              │
                         ┌────▼─────────────────────┐
                         │   VPS  (dc=cloud)         │  public IPv4 + IPv6
                         │                           │
                         │  Caddy   — public ingress │
                         │  Netbird — mesh control   │
                         │  Nomad   — scheduler      │
                         │  Consul  — service disco  │
                         └────┬──────────────────────┘
                              │  WireGuard mesh (Netbird)
                              │  Consul WAN federation
          ┌───────────────────┴────────────────────────────┐
          │              dc=home                           │
          │                                                │
   ┌──────▼──────┐    ┌──────────────┐   ┌──────────────┐ │
   │ Storage 1   │    │   Light 1    │   │   Light 2    │ │
   │             │    │              │   │              │ │
   │ Garage      │    │ Edge worker  │   │ Edge worker  │ │
   │ geesefs*    │    │ Nomad server │   │ Nomad server │ │
   │ Jellyfin    │    │ Consul server│   │ Consul server│ │
   │ Kavita      │    │ CoreDNS      │   │ CoreDNS      │ │
   │ CoreDNS     │    └──────────────┘   └──────────────┘ │
   └──────┬──────┘                                        │
          │                                               │
   ┌──────▼──────┐    ┌──────────────┐                    │
   │ Storage 2   │    │  GPU node    │                    │
   │  ...same... │    │  Ollama      │                    │
   └─────────────┘    └──────────────┘                    │
                                                          │
          └────────────────────────────────────────────── ┘

* geesefs runs as a host-level FUSE mount, not inside any container
```

---

## Layer Breakdown

### 1. Mesh Networking — Netbird

Netbird provides the encrypted WireGuard overlay. Three server components run on the VPS:

| Component | Port | Role |
|-----------|------|------|
| `netbird-management` | 443 | Device enrollment, key exchange, ACL policy |
| `netbird-signal` | 10000 | ICE/hole-punch signaling between peers |
| `netbird-relay` | 3478 UDP | TURN relay fallback for stubborn NAT |

All three share the single public IPv4. Every node joins with a one-time setup key:

```sh
netbird up \
  --management-url https://netbird.yourdomain.com \
  --setup-key <one-time-key>
```

After joining, the node receives a stable `10.x.x.x` Netbird address. All inter-service
communication uses these addresses. Static IPv6 on home nodes means most connections are
direct WireGuard tunnels; the relay is a fallback only.

### 2. Orchestration — Nomad + Consul

Nomad schedules workloads as native processes (`raw_exec` driver). Consul handles service
discovery, health checking, and datacenter-aware DNS. Three light nodes run Nomad and
Consul in server mode; all nodes run client agents.

**Services run as native processes, not containers.** Nomad's `artifact` stanza downloads
and caches each service binary directly — version-pinned in the job spec, no image registry
required. System-level dependencies (fuse3, ffmpeg) are installed once by Ansible during
node bootstrap.

**Capability constraints** in each node's client config drive placement:

```hcl
# /etc/nomad/client.hcl
client {
  meta {
    "has_storage" = "true"
    "has_gpu"     = "false"
    "role"        = "edge"   # vps | storage | edge | forge
  }
}
```

Jobs self-select onto matching nodes:

```hcl
constraint {
  attribute = "${meta.has_storage}"
  value     = "true"
}
```

### 3. Consul Datacenters — Proximity-Aware Routing

Consul federates two datacenters over the Netbird WAN mesh:

| Datacenter | Nodes | Purpose |
|------------|-------|---------|
| `dc=home` | Storage nodes, home light nodes, GPU nodes | Primary compute + storage |
| `dc=cloud` | VPS, remote light nodes | Always-on coordination + public ingress |

Consul DNS returns results from the **local datacenter first**, falling back to the remote
datacenter only if no healthy local instances exist. This means:

- A client on the home LAN querying `ollama.service.consul` gets the home GPU node's IP
  directly — no VPS hop, no proxy, direct WireGuard path
- A remote client gets routed to whichever datacenter has a healthy instance

```
Home client → ollama.service.consul
  → local Consul agent (dc=home)
    → home GPU node :11434  ← direct WireGuard, no VPS involved

Remote client → ollama.service.consul
  → local Consul agent (dc=cloud)
    → falls back to dc=home (no GPU in cloud)
      → home GPU node :11434  ← over WireGuard, VPS not in data path
```

WAN federation is configured with `retry_join_wan` pointing each datacenter's Consul
servers at the other's Netbird IPs. Consul WAN gossip uses port 8302.

### 4. Storage — Garage + geesefs

Garage is a distributed S3-compatible object store designed for heterogeneous hardware.
`GARAGE_REPLICATION_FACTOR` equals the number of storage nodes so every node holds a
complete copy of every object. Jellyfin reads from `localhost:3900` (local Garage) —
effectively local disk throughput, sufficient for 4K direct play.

| Bucket | Contents | Host mount path |
|--------|----------|-----------------|
| `hyphae-books` | Kavita library | `/mnt/hyphae/books` |
| `hyphae-shows` | TV shows | `/mnt/hyphae/shows` |
| `hyphae-movies` | Films, 4K Blu-ray rips | `/mnt/hyphae/movies` |
| `hyphae-music` | Music library | `/mnt/hyphae/music` |

**geesefs runs as a host-level FUSE mount** managed by a Nomad `raw_exec` task. Because
it mounts directly into the host filesystem (not a container's mount namespace), the
mounts are:
- Visible to all processes on the host, including Jellyfin and Kavita running under Nomad
- Debuggable over SSH without entering any container
- Persistent across Jellyfin/Kavita restarts — the mount stays up independently

Host requires `fuse3` installed and `user_allow_other` in `/etc/fuse.conf`. This is
handled by the Ansible bootstrap playbook.

**Garage K2V** (built into the Garage binary) stores durable cluster configuration —
things that need to survive restarts but change infrequently. Not used for ephemeral
health state (Consul handles that).

### 5. Secrets — SOPS + age

Cluster-wide secrets live encrypted in `secrets/secrets.yaml`, committed to the repo.
Each node operator receives an age private key out-of-band, stored on the host at
`/etc/hyphae/age.key` (chmod 600, written by Ansible).

A systemd oneshot unit `hyphae-secrets.service` runs before Nomad on each boot,
decrypting secrets to `/run/secrets/` (tmpfs):

```
hyphae-secrets.service (oneshot)
  └── nomad.service
        └── consul.service  (already running, started by Ansible)
```

Nomad jobs reference `/run/secrets/` directly in their config templates. Secrets vanish
on reboot until decrypted again.

Secrets stored:
- `garage-rpc-secret` — cluster authentication between Garage nodes
- `garage-admin-token` — Garage admin API
- `garage-metrics-token` — Garage metrics scrape
- `s3-access-key-id` / `s3-secret-key` — geesefs S3 credentials
- `kavita-token-key` — Kavita API authentication

### 6. Internal DNS — CoreDNS + Consul

CoreDNS runs on every node, handling `*.hyphae.internal`. It forwards service lookups
to the local Consul agent (port 8600), which applies datacenter-aware routing:

```
Client → *.hyphae.internal
  → CoreDNS (node-local, port 53)
    → Consul DNS (node-local, port 8600)
      → returns healthy instances, local DC first
```

Devices on the home LAN set their DNS to the local node's IP via DHCP or Netbird's
DNS override. Remote devices use Netbird's DNS settings to point `*.hyphae.internal`
at their nearest Consul agent.

### 7. Public Ingress — Caddy

Caddy runs on the VPS as the sole internet-facing component. It terminates TLS
(automatic Let's Encrypt) and reverse-proxies to internal services over Netbird.

```
forge.yourdomain.com  → Forgejo     (dc=home, via Netbird)
app.yourdomain.com    → Edge workers (dc=home + dc=cloud, load balanced)
```

Caddy's upstream lists are populated via Consul-template, updating automatically as
services come and go. **Caddy is only involved in public internet traffic.** Mesh-internal
clients bypass Caddy entirely and use Consul DNS for direct connections.

### 8. LLM Inference — Ollama

Each GPU-capable node runs an Ollama instance as a `raw_exec` Nomad task. GPU
passthrough is a direct device stanza in the job spec — no container toolkit required.

Clients (internal or via Caddy) hit `ollama.service.consul`, which Consul DNS resolves
to a healthy Ollama instance in the nearest datacenter. No additional proxy layer.

True distributed tensor parallelism is not used — network latency makes all-reduce
operations too slow without direct GPU interconnects. Each node runs a complete model;
Consul routes at the request level.

### 9. Edge Serverless — Spin / workerd

Edge workers run on all light nodes as `raw_exec` Nomad service jobs. Nomad distributes
instances across available edge nodes automatically. WASM/JS bundles are stored in Garage
S3 and fetched by workers on startup.

Public traffic reaches edge workers via Caddy on the VPS. Internal traffic hits them
directly via Consul DNS.

### 10. Git + CI/CD — Forgejo

Forgejo (single Go binary, `raw_exec`) runs on whichever node carries the `forge` role.
Forgejo Actions runners run on edge nodes — these use Docker for job isolation since
runner tasks execute arbitrary user code.

LFS objects and CI artifacts are stored in Garage S3 via Forgejo's S3 backend config.

---

## Service Catalog

| Service | Driver | Constraint | Ports |
|---------|--------|------------|-------|
| Garage | `raw_exec` | `meta.has_storage = true` | 3900, 3901, 3903 |
| geesefs | `raw_exec` (host FUSE) | `meta.has_storage = true` | — |
| Jellyfin | `raw_exec` | `meta.has_storage = true` | 8096 |
| Kavita | `raw_exec` | `meta.has_storage = true` | 5000 |
| Ollama | `raw_exec` | `meta.has_gpu = true` | 11434 |
| Forgejo | `raw_exec` | `meta.role = forge` | 3000, 22 |
| Forgejo runner | `docker` | `meta.role = edge` | — |
| Spin/workerd | `raw_exec` | `meta.role = edge` | 3000 |
| CoreDNS | `raw_exec` | all nodes | 53 |
| Caddy | `raw_exec` | `meta.role = vps` | 80, 443 |
| Netbird servers | systemd | VPS only | 443, 10000, 3478 |
| Nomad agent | systemd | all nodes | 4646, 4647, 4648 |
| Consul agent | systemd | all nodes | 8300, 8301, 8500, 8600 |

Nomad agent, Consul agent, and Netbird client are installed as systemd services by
Ansible during bootstrap — they are infrastructure, not workloads.

---

## Node Onboarding

```sh
# 1. Generate a Netbird setup key in the management UI

# 2. Add the node to the Ansible inventory with its capabilities
#    inventory/hosts.ini:
#      [storage]
#      new-node ansible_host=192.168.1.x

# 3. Run the bootstrap playbook
ansible-playbook bootstrap.yml -l new-node

# The playbook:
#   - installs fuse3, ffmpeg, and other system deps
#   - installs Nomad, Consul, Netbird binaries
#   - writes /etc/nomad/client.hcl with correct client.meta from inventory vars
#   - writes /etc/consul/consul.hcl with correct datacenter assignment
#   - writes /etc/hyphae/age.key from vault/secrets
#   - enables and starts hyphae-secrets, consul, nomad as systemd services
#   - runs: netbird up --management-url ... --setup-key ...
#
# Nomad sees the new client, applies matching job constraints, schedules workloads.
# No further action needed.
```

**Hardware capability detection** (optional helper, generates inventory vars):

```sh
./bootstrap-detect.sh   # probes GPU, disk size; prints suggested inventory vars
```

---

## First-Time Cluster Bootstrap

After the first two storage nodes are running, lay out the Garage storage topology once:

```sh
garage status   # note the node IDs

garage layout assign <node-id-1> --zone home --capacity 8T
garage layout assign <node-id-2> --zone home --capacity 8T
garage layout apply --version 1
```

Garage begins replicating. Each additional storage node needs the same treatment.

---

## Port Reference

| Service | Port | Protocol | Scope |
|---------|------|----------|-------|
| Netbird management | 443 | TCP | Public (VPS) |
| Netbird signal | 10000 | TCP | Public (VPS) |
| Netbird relay | 3478 | UDP | Public (VPS) |
| Caddy HTTP | 80 | TCP | Public (VPS) |
| Caddy HTTPS | 443 | TCP | Public (VPS) |
| Garage S3 API | 3900 | TCP | Mesh-internal |
| Garage RPC | 3901 | TCP | Mesh-internal |
| Garage admin | 3903 | TCP | Mesh-internal |
| Jellyfin | 8096 | TCP | Mesh-internal |
| Kavita | 5000 | TCP | Mesh-internal |
| Ollama | 11434 | TCP | Mesh-internal |
| Forgejo HTTP | 3000 | TCP | Mesh-internal + Caddy |
| Forgejo SSH | 22 | TCP | Mesh-internal + Caddy |
| Spin/workerd | 3000 | TCP | Mesh-internal + Caddy |
| Consul DNS | 8600 | TCP/UDP | Node-local |
| Consul HTTP | 8500 | TCP | Mesh-internal |
| Consul RPC | 8300 | TCP | Mesh-internal |
| Consul Serf LAN | 8301 | TCP/UDP | Mesh-internal |
| Consul Serf WAN | 8302 | TCP/UDP | Mesh-internal (DC federation) |
| Nomad HTTP | 4646 | TCP | Mesh-internal |
| Nomad RPC | 4647 | TCP | Mesh-internal |
| Nomad Serf | 4648 | TCP/UDP | Mesh-internal |
| CoreDNS | 53 | TCP/UDP | Node-local |
