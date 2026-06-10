with pkgs;
{
  script = # bash
    ''
      ${hello}/bin/hello
    '';
}
