{
  description = "Minimal flake with cowsay";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.cowsay ];

        shellHook = ''
          cowsay "Hello from Nix!"
        '';
      };
    };
}
