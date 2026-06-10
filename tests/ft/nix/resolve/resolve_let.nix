let
  greeting = "hi from let";
in
{
  script = # bash
    ''
      ${greeting}/x
    '';
}
