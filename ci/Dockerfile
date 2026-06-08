# Build the headless test devShell from the project's ROOT flake. The flake
# pulls the Neovim toolchain from slop-env (overlay in slop-env/nix + config in
# slop-env/nvim) — the single source of truth shared with local dev. This
# replaces the former ci/nix/kickstart-nix.nvim duplicate. See docs/adr/0004.
#
# devShells.test references only nixpkgs/flake-utils/gen-luarc; the jail/claude
# inputs (jail-nix, llm-agents, nix-slop-dev) are never referenced, so lazy
# flake evaluation never fetches them — at build time or at `nix develop` time.
FROM nixos/nix:latest AS builder

WORKDIR /build

# The repo root is the flake (flake.nix imports ./slop-env). Bring in the flake,
# the toolchain source, and the project so `.#test` evaluates and the suite runs.
COPY flake.nix flake.lock ./
COPY slop-env ./slop-env
COPY lua ./lua
COPY plugin ./plugin
COPY tests ./tests

RUN nix --extra-experimental-features "nix-command flakes" \
    --option filter-syscalls false build .#devShells.x86_64-linux.test

# Capture the build closure so the final image has the toolchain without network.
RUN mkdir /tmp/nix-store-closure && cp -R $(nix-store -qR result/) /tmp/nix-store-closure

# Stage 2: Final image – use a base that already has Nix (to preserve system libraries)
FROM nixos/nix:latest

WORKDIR /ninjection

COPY --from=builder /tmp/nix-store-closure /nix/store

# The flake + sources needed to `nix develop .#test` and run the suite at runtime.
COPY --from=builder /build/flake.nix /build/flake.lock ./
COPY --from=builder /build/slop-env ./slop-env
COPY --from=builder /build/lua ./lua
COPY --from=builder /build/plugin ./plugin
COPY --from=builder /build/tests ./tests

COPY ci/docker-entrypoint.sh /usr/local/bin/nvim-dev-entry
RUN chmod +x /usr/local/bin/nvim-dev-entry

ENTRYPOINT ["/usr/local/bin/nvim-dev-entry"]
