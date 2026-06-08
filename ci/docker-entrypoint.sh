#!/usr/bin/env bash
set -euo pipefail

# Run the passed command inside the root flake's headless test devShell.
# WORKDIR is /ninjection, so $PWD in the shellHook resolves the
# ~/.config/nvim-dev -> slop-env/nvim symlink correctly.
exec nix develop /ninjection#test \
  --extra-experimental-features "nix-command flakes" \
  --command "$@"
