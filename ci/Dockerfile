FROM nixos/nix:latest AS builder

WORKDIR /tmp/build

COPY ./ci/nix/kickstart-nix.nvim ./kickstart-nix.nvim

WORKDIR /tmp/build/kickstart-nix.nvim

RUN nix --extra-experimental-features "nix-command flakes" \
    --option filter-syscalls false build .#devShells.x86_64-linux.default

# Optionally, capture the closure to cache all dependencies.
RUN mkdir /tmp/nix-store-closure && cp -R $(nix-store -qR result/) /tmp/nix-store-closure

# Stage 2: Final image – use a base that already has Nix (to preserve system libraries)
FROM nixos/nix:latest

WORKDIR /ninjection

# Safe COPY with fallback
COPY --from=builder /tmp/nix-store-closure /nix/store
COPY --from=builder /tmp/build/kickstart-nix.nvim/result /ninjection

COPY ../ci/nix /ninjection/ci/nix
COPY ../lua /ninjection/lua
COPY ../plugin /ninjection/plugin
COPY ../tests /ninjection/tests

COPY ./ci/docker-entrypoint.sh /usr/local/bin/nvim-dev-entry
RUN chmod +x /usr/local/bin/nvim-dev-entry

ENV VIMRUNTIME="/ninjection/share/nvim/runtime"
ENV NVIM_PACKPATH="/ninjection/pack/myNeovimPackages/start/*"
ENV NVIM_RTP="/ninjection/share/nvim/runtime"

ENTRYPOINT ["/usr/local/bin/nvim-dev-entry"]
