{
  description = "Hyphae - Distributed Document Storage System";

  # Flake inputs
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # Stable Nixpkgs
  };

  # Flake outputs
  outputs =
    { self, ... }@inputs:
    {
      # Export NixOS module for integration into other flakes
      nixosModules.default = { config, lib, pkgs, ... }: {
        imports = [
          ./yggdrasil.nix
          ./garage.nix
        ];
      };

      # Convenience alias
      nixosModules.hyphae = self.nixosModules.default;
    };
}
