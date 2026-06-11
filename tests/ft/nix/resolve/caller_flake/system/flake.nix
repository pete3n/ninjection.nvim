{
  description = "My Basic NixOS System Configuration Flake";

  inputs = {
    # You can change 'nixos-unstable' to a specific release like 'nixos-23.11'
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations = {
      # Replace "my-hostname" with the hostname set in your configuration.nix
      my-hostname = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux"; # Change to "aarch64-linux" if on ARM
        modules = [
          ./hardware-configuration.nix
          ./configuration.nix
        ];
      };
    };
  };
}
