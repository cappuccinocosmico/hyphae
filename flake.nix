{
  description = "An empty flake template that you can adapt to your own environment";

  # Flake inputs
  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # Stable Nixpkgs

  # Flake outputs
  outputs =
    { self, ... }@inputs:
    let
      # The systems supported for this flake's outputs
      supportedSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux
        "x86_64-darwin" # 64-bit Intel macOS
        "aarch64-darwin" # 64-bit ARM macOS
      ];

    in
    {
      # NixOS configurations for hyphae nodes
      nixosConfigurations = {
        # Example node configuration - customize for each machine
        hyphae-node = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            # Basic system configuration would go here
            # ./hardware-configuration.nix

            # Import hyphae service modules
            ./yggdrasil.nix
            ./garage.nix
          ];
        };
      };
    };
}
