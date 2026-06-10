with { greeting = "hi from with"; };
{
  script = # bash
    ''
      ${greeting}/x
    '';
}
