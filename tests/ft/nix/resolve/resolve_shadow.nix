let
  greeting = "hi from let";
in
with { greeting = "hi from with"; };
{
  script = # bash
    ''
      ${greeting}/x
    '';
}
