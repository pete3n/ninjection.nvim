{ }:
{
  injected_sh_edit = # sh 
    ''
#!/usr/bin/env bash

basedir=$(dirname "$(readlink -f "$0")")

# figure out which action to perform
action="$1"

case "$action" in
install)
  ;;
uninstall)
  ;;
*)
  echo "Unrecognized action: $action"
  echo "Usage: $0 [install|uninstall] [--symlink]"
  exit 1
esac
    '';
}
