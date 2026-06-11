# Not listed in any nixosSystem modules: the with environment's formal `pkgs`
# genuinely lives in an unseen caller.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    wget
  ];
}
