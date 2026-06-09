{ pkgs }:
{
  script = # bash
    ''
      ${pkgs.hello}/bin/hello
      echo ''${HOME}
    '';
}
