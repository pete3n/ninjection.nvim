let
  attrs = {
    greeting = "hi from with let";
  };
in
with attrs;
{
  script = # bash
    ''
      ${greeting}/x
    '';
}
