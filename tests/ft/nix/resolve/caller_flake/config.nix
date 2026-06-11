{ pkgs, lib }:
{
  script = # bash
    ''
      ${pkgs.hello}/bin/hello
      echo "nixpkgs version ${lib.version}"
    '';
}
