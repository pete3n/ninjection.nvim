# CI shares the local Neovim toolchain from a single source

The e2e test environment is defined once, in `slop-env/` (the Neovim overlay in
`slop-env/nix/` and the runtime config in `slop-env/nvim/`), and consumed through
the root `flake.nix`. CI builds its test image from that same source rather than
from a parallel copy. Concretely, the root flake exposes a headless
`devShells.test` — the same `nvim-dev` derivation, packpath, and
`~/.config/nvim-dev → slop-env/nvim` symlink the local devShell uses, minus the
jail/claude/sandbox machinery — and `ci/Dockerfile` builds from it. The former
duplicate, `ci/nix/kickstart-nix.nvim/`, is deleted.

We adopted this after the test harness diverged between environments: CI ran a
copy pinned to nixpkgs `nixos-25.05` (Neovim 0.11.2) while local development ran
`slop-env/` on `nixos-26.05` (Neovim 0.12.2), and the two config copies had
already drifted (old `require('lspconfig').setup` vs. `vim.lsp.config`/`enable`,
`nixfmt` vs. `nixfmt-rfc-style`). The whole harness depends on one fragile chain
— Plenary spawns each spec in a child Neovim that loads `~/.config/nvim-dev/init.lua`,
and that `init.lua` is what wires `NVIM_PACKPATH` onto the packpath, sets the
indent options that make `lua_ls` emit spaces not tabs, and configures the LSPs
(see [the test-harness notes](../../tests/run.sh)). Two copies of that chain means
two ways for it to silently rot. One source means the version local developers
run is the version CI gates on.

A flake may only import paths inside its own root, so a sub-flake under `ci/nix/`
cannot import `../../../slop-env`. Routing CI through the root flake (which already
does `import ./slop-env/nix/neovim-overlay.nix`) is therefore the mechanism that
makes a single source possible, not merely the tidier option.

## Consequences

- The e2e Docker path is the only CI surface that consolidates here. The
  binary-download workflows (`typecheck`, `typecheck-debug`, `gendocs`, `style`,
  `lint`) fetch upstream release artifacts and are not Nix-based; they pin their
  Neovim / lua-language-server / StyLua versions independently and must be bumped
  to match `slop-env` separately to keep the environments aligned. Version parity
  across those is a manual obligation, not something the flake enforces.
- `e2e-test.yml` is unchanged: `docker run … nvim-dev --headless -c
  "PlenaryBustedDirectory <dir>" -c qa`, with no `minimal_init`. A `minimal_init`
  would replace `init.lua` and break the bootstrap chain above, so the harness
  must always run the spec child through the real dev config.
- Test fixtures are opened by **relative** path (`tests/ft/…`), never the Docker
  WORKDIR absolute (`/ninjection/…`); the working directory is the project root in
  both environments.
- The root flake gains a CI-facing output (`devShells.test`). Its inputs include
  `jail-nix` / `llm-agents` / `nix-slop-dev`; building `test` must not force those
  (they stay lazy). If a build does pull them, the fallback is to make `slop-env/`
  its own flake so a lean CI consumer can import it without the agent inputs.
- Bumping the shared source bumps everything at once — Neovim, treesitter
  grammars, `lua_ls`, plugins — so a single nixpkgs bump can change formatting and
  type-check output together. That is the intended trade: one knob, one
  verification pass, no per-environment surprises.
