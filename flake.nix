{
  description = "Hyphae cluster bootstrap environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, system-manager }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      # Shared module list for both system-manager (non-NixOS) and nixosConfigurations.
      nodeModules =
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
        }:
        [
          ./nix/modules/fuse.nix
          ./nix/modules/hyphae-secrets.nix
          (import ./nix/modules/consul.nix {
            datacenter = consulDatacenter;
            isServer = consulIsServer;
            bootstrapExpect = consulBootstrapExpect;
            retryJoin = consulRetryJoin;
            retryJoinWan = consulRetryJoinWan;
          })
          (import ./nix/modules/nomad.nix {
            inherit nodeRole hasStorage hasGpu;
            isServer = nomadIsServer;
            bootstrapExpect = nomadBootstrapExpect;
          })
          ./nix/modules/netbird.nix
        ];

      # Build a system-manager config for a non-NixOS cluster node.
      # The key in systemConfigs must match inventory_hostname in Ansible so the
      # nix role can run:
      #   nix run .#system-manager -- switch --flake /opt/hyphae#<hostname>
      mkNode = args @ { system ? "x86_64-linux", ... }:
        system-manager.lib.makeSystemConfig {
          modules = [ { nixpkgs.hostPlatform = system; } ]
            ++ nodeModules (builtins.removeAttrs args [ "system" ]);
        };

      # Build a NixOS config for a cluster node running NixOS.
      # Users are managed declaratively here (unlike non-NixOS where Ansible handles them).
      # Pass extraModules for host-specific config (hardware-configuration.nix, etc.).
      # Deploy with: nixos-rebuild switch --flake .#<hostname>
      mkNixosNode = args @ { system ? "x86_64-linux", extraModules ? [], ... }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = nodeModules (builtins.removeAttrs args [ "system" "extraModules" ]) ++ [
            {
              users.users.consul = { isSystemUser = true; group = "consul"; };
              users.users.nomad  = { isSystemUser = true; group = "nomad";  };
              users.groups.consul = {};
              users.groups.nomad  = {};
            }
          ] ++ extraModules;
        };
    in
    {
      # Per-node system-manager configurations (non-NixOS hosts).
      # Add an entry here for every host in ansible/inventory/hosts.ini,
      # using the exact inventory_hostname as the attribute name.
      systemConfigs = {
        storage1 = mkNode { nodeRole = "storage"; consulDatacenter = "home"; hasStorage = true; };
        vps1     = mkNode { nodeRole = "vps";     consulDatacenter = "cloud"; };
        light1   = mkNode { nodeRole = "edge";    consulDatacenter = "home"; };
        gpu1     = mkNode { nodeRole = "edge";    consulDatacenter = "home"; hasGpu = true; };
      };

      # Per-node NixOS configurations (NixOS hosts).
      # Add hardware-configuration.nix and any host-specific NixOS options via extraModules.
      # Deploy with: nixos-rebuild switch --flake .#<hostname>
      nixosConfigurations = {
        # storage1 = mkNixosNode {
        #   nodeRole = "storage"; consulDatacenter = "home"; hasStorage = true;
        #   extraModules = [ ./hosts/storage1/hardware-configuration.nix ];
        # };
      };

      # Expose the pinned system-manager binary as a runnable app.
      # Ansible nix role runs: nix run /opt/hyphae#system-manager -- switch --flake /opt/hyphae#<hostname>
      apps = forAllSystems (system: {
        system-manager = {
          type = "app";
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
              # garage # uncomment when garage is in nixpkgs stable
              ansible
            ];
          };
        }
      );
    };
}
