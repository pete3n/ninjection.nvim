# Environment

You are running inside a sandboxed development environment on NixOS.

## Constraints
- By default network access is restricted to your API endpoint only. All other
  connections must be requested and whitelisted before fetch will work.
- Filesystem access is limited to the current project directory and
  essential config paths. You cannot read or modify files outside the
  project.
- The Nix store is not directly accessible. Tools available to you are
  those explicitly provided in the devShell.
