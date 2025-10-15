{
  description = "Hyphae - Distributed Document Storage System";

  # Flake inputs
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # Stable Nixpkgs
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  # Flake outputs
  outputs =
    { self, agenix, ... }@inputs:
    {
      # Export NixOS module for integration into other flakes
      nixosModules.default = { config, lib, pkgs, ... }: {
        imports = [
          agenix.nixosModules.default
          ./yggdrasil.nix
          ./garage.nix
          ./kavita.nix
          ./jellyfin.nix
        ];
      };

      # Convenience alias
      nixosModules.hyphae = self.nixosModules.default;
    };
}
