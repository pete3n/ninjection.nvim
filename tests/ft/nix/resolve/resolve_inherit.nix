let
  inherit ({ greeting = "hi from inherit"; }) greeting;
in
{
  script = # bash
    ''
      ${greeting}/x
    '';
}
