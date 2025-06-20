#!/usr/bin/env bash
set -euo pipefail

# Use devShell environment to run the passed command
exec nix develop /ninjection/ci/nix/kickstart-nix.nvim \
  --extra-experimental-features "nix-command flakes" \
  --command "$@"
