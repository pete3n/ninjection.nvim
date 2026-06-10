{ pkgs, lib }:
{
  script = # bash
    ''
      ${pkgs.hello}/bin/hello
    '';
}
