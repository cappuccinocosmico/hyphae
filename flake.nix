{
  description = "Hyphae cluster bootstrap environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, system-manager, sops-nix, disko }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        # sops-nix overlay adds pkgs.sops-install-secrets (and friends).
        overlays = [ sops-nix.overlays.default ];
      };

      # Build a system-manager config for a non-NixOS cluster node.
      # The key passed as `systemConfigs.<key>` must match inventory_hostname
      # in Ansible so the nix role can run:
      #   nix run .#system-manager -- switch --flake /opt/hyphae#<hostname>
      mkNode =
        { nodeRole
        , consulDatacenter
        , hasStorage ? false
        , hasGpu ? false
        , consulIsServer ? false
        , consulBootstrapExpect ? 3
        , consulRetryJoin ? []
        , consulRetryJoinWan ? []
        , nomadIsServer ? false
        , nomadBootstrapExpect ? 3
        , system ? "x86_64-linux"
        # Additional modules for per-node customisation (e.g. sops.secrets declarations).
        , extraModules ? []
        }:
        system-manager.lib.makeSystemConfig {
          modules = [
            {
              nixpkgs.hostPlatform = system;
              # Apply overlay so pkgs.sops-install-secrets is available in all modules.
              nixpkgs.overlays = [ sops-nix.overlays.default ];
            }
            ./nix/modules/fuse.nix
            ./nix/modules/sops.nix
            (import ./nix/modules/consul.nix {
              datacenter      = consulDatacenter;
              isServer        = consulIsServer;
              bootstrapExpect = consulBootstrapExpect;
              retryJoin       = consulRetryJoin;
              retryJoinWan    = consulRetryJoinWan;
            })
            (import ./nix/modules/nomad.nix {
              inherit nodeRole hasStorage hasGpu;
              isServer        = nomadIsServer;
              bootstrapExpect = nomadBootstrapExpect;
            })
            ./nix/modules/netbird.nix
          ] ++ extraModules;
        };
    in
    {
      # ── NixOS nodes ───────────────────────────────────────────────────────
      # Full NixOS systems managed via nixos-anywhere + nixos-rebuild.
      # These are NOT in systemConfigs (system-manager is for non-NixOS hosts).
      nixosConfigurations.vps1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./nix/hosts/vps1/disk-config.nix
          ./nix/hosts/vps1/configuration.nix
          ./nix/modules/netbird-relay.nix
        ];
      };

      # ── system-manager nodes (non-NixOS hosts) ────────────────────────────
      # Add an entry here for every non-NixOS host in ansible/inventory/hosts.ini,
      # using the exact inventory_hostname as the attribute name.
      systemConfigs = {
        storage1 = mkNode { nodeRole = "storage"; consulDatacenter = "home"; hasStorage = true; };
        light1   = mkNode { nodeRole = "edge";    consulDatacenter = "home"; };
        gpu1     = mkNode { nodeRole = "edge";    consulDatacenter = "home"; hasGpu = true; };
      };

      # Expose the pinned system-manager binary as a runnable app.
      # Ansible nix role runs: nix run /opt/hyphae#system-manager -- switch --flake /opt/hyphae#<hostname>
      apps = forAllSystems (system: {
        system-manager = {
          type    = "app";
          program = "${system-manager.packages.${system}.system-manager}/bin/system-manager";
        };
      });

      # Operator shell: everything needed for cluster management and day-2 ops.
      devShells = forAllSystems (system:
        let pkgs = pkgsFor system; in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nomad
              consul
              netbird
              sops
              age
              ansible
              nixos-anywhere  # deploy vps1 (and future NixOS nodes)
              # garage        # uncomment when garage is in nixpkgs stable
            ];
          };
        }
      );
    };
}
