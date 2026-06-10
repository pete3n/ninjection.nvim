#!/usr/bin/env bash
# Local test runner for the ninjection.nvim Plenary/busted e2e suite.
#
# Invokes the suite exactly as the GitHub Actions e2e workflow does
# (.github/workflows/e2e-test.yml): `nvim-dev --headless -c "PlenaryBustedDirectory
# <dir>" -c qa`. No special init is needed — Plenary spawns each spec in a child
# Neovim that loads the dev config (~/.config/nvim-dev -> slop-env/nvim) via
# NVIM_APPNAME, and that init.lua wires up packpath, indent options, and LSPs.
#
# Requires the Nix devShell (provides `nvim-dev` and the ~/.config/nvim-dev
# symlink created by the flake's shellHook).
#
# Usage:
#   tests/run.sh              # run all groups
#   tests/run.sh health       # health | nix-lua | nix-bash | lua-nix
#   tests/run.sh tests/ft/... # an explicit directory or spec path
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

NVIM_BIN="${NVIM_BIN:-nvim-dev}"

# Default test groups (same partitioning as .github/workflows/e2e-test.yml).
TEST_GROUPS=(
	"tests/health"
	"tests/ft/nix/lua"
	"tests/ft/nix/bash"
	"tests/ft/nix/resolve"
	"tests/ft/lua/nix"
)

if [ "$#" -gt 0 ]; then
	case "$1" in
		health) TEST_GROUPS=("tests/health") ;;
		nix-lua) TEST_GROUPS=("tests/ft/nix/lua") ;;
		nix-bash) TEST_GROUPS=("tests/ft/nix/bash") ;;
		nix-resolve) TEST_GROUPS=("tests/ft/nix/resolve") ;;
		lua-nix) TEST_GROUPS=("tests/ft/lua/nix") ;;
		*) TEST_GROUPS=("$1") ;;
	esac
fi

if ! command -v "$NVIM_BIN" >/dev/null 2>&1; then
	echo "error: '$NVIM_BIN' not found on PATH. Are you in the Nix devShell?" >&2
	exit 127
fi

fail=0
for group in "${TEST_GROUPS[@]}"; do
	echo "═══ Running: $group ═══"
	"$NVIM_BIN" --headless \
		-c "PlenaryBustedDirectory $group" \
		-c "qa" || fail=1
	echo
done

if [ "$fail" -ne 0 ]; then
	echo "✗ Some tests failed."
	exit 1
fi
echo "✓ All tests passed."
