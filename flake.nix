{
  description = "Hyphae - Distributed Document Storage System";

  # Flake inputs
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # Stable Nixpkgs
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  # Flake outputs
  outputs =
    { self, sops-nix, ... }@inputs:
    {
      # Export NixOS module for integration into other flakes
      nixosModules.default = { config, lib, pkgs, ... }: {
        imports = [
          sops-nix.nixosModules.sops
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
