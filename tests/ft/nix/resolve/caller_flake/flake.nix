{
  description = "Resolve fixture: the caller binds pkgs from the nixpkgs flake input";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.${builtins.currentSystem};
    in
    {
      config = import ./config.nix {
        inherit pkgs;
        lib = pkgs.lib;
      };
    };
}
