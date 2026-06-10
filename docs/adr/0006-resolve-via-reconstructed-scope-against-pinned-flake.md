# Resolve interpolations via Treesitter-reconstructed scope against the pinned flake

`resolve()` produces the *real evaluated value* of a parent interpolation — the
deferred "real-value resolution" of ADR-0005, e.g. Nix `${pkgs.hello}` → its
store path `/nix/store/…-hello`. An interpolation buried inside a string inside a
derivation argument is **not addressable** (there is no `nix eval` primitive for
"evaluate the expression at this byte-range in its lexical scope"), so resolution
cannot rely on a flake attribute path. Instead, Treesitter walks outward from the
interpolation node, collects the lexical bindings in scope, and synthesizes a
self-contained expression evaluated with `nix eval --raw --expr`. This keeps all
structural introspection inside Treesitter (ADR-0002) — scope reconstruction *is*
a structural-introspection problem — rather than reaching for a hand-rolled Nix
parser. Resolved values are surfaced non-destructively (virtual text, hover
float), never written into the buffer, preserving the round-trip's
no-silent-mutation discipline.

The `pkgs` the synthesized expression evaluates against comes from the project's
**pinned flake input** (`builtins.getFlake "<root>"` → `.inputs.nixpkgs`), never
the ambient `<nixpkgs>` channel. The channel is the wrong version relative to what
the build uses, is impure, and may be absent in the offline CI image — so it is
both inaccurate and untestable there. The pinned input is reproducible,
offline-resolvable from the store, and the only source that can ever reach the
stated destination of *complete accuracy* (overlays/config included). Store paths
are available at **evaluation** time, so resolving never realises a derivation —
no builds are triggered from the editor.

## Considered Options

- **Evaluate an addressable flake output / attr path** (`nix eval .#myvar.outPath`).
  Rejected: the canonical interpolation (inside a derivation's string argument,
  the `writePython3Bin` shape) has no attribute path to address. Works only for
  top-level bindings, which is not the feature.
- **Channel `<nixpkgs>` + `--impure`.** Rejected: trivially simple to synthesize,
  but ambient-versioned, impure, absent in offline CI, and a dead end for accuracy.
- **Best-effort conventional defaults for free variables** (`pkgs` →
  `import <nixpkgs> {}`). Not adopted as the end state: it cannot be accurate under
  overlays/config. May return as a fallback, but accuracy requires the *real*
  `pkgs` the caller supplies.

## Consequences

- **The feasibility boundary is self-contained vs. free variable.** When the
  binding chain bottoms out inside the file (a `let`/`with`/`inherit` in view),
  the interpolation is resolvable. When it ends in a **free variable** — a function
  parameter (`{ pkgs, lib }:`) whose value lives in an unseen caller — it is not
  resolvable from the file alone, because no single-file introspection recovers the
  caller's value. The POC resolves only self-contained interpolations and reports a
  clear "bound by caller" condition otherwise. Reaching real-world function-of-pkgs
  files (NixOS modules, package definitions, `writePython3Bin`) is future work and
  ultimately requires knowing how the file is *instantiated*, not just its text.
- **Resolution is an engine, not a verb.** `ninjection/resolve.lua` exposes
  `resolve(node, bufnr)` returning data; the `ninjection.resolve()` verb renders
  it (virtual text now, hover float as a sibling renderer). `edit()` consumes the
  same engine later to fill child-buffer placeholders with real values instead of
  the `""`/`nil` default — mirroring the transform/render split of ADR-0001.
- **New CI cost the other verbs never carried.** `resolve()` shells out to `nix`.
  The ADR-0004 Docker image copies only the *build closure* of `.#test` — the
  toolchain built from nixpkgs, not the nixpkgs *source tree* that `nix eval`
  reads. An offline e2e test therefore requires deliberately seeding the eval
  fixture's nixpkgs source (and the eval-time closure of the resolved package)
  into the image. The plan is to prove the engine locally first (specs that skip
  when `nix`/nixpkgs-source is unavailable) and treat offline-CI resolution as a
  separate, explicitly-scoped follow-up.
- **`getFlake` on a local uncommitted tree is impure**, so dev-tree resolution may
  still need `--impure` even though the channel is never touched — a flag detail,
  not a strategy change.
- **Real-value resolution re-raises the extmark question ADR-0005 deferred.** Once
  a resolved value is shown *and the user accepts it into the child buffer*, the
  interpolation site's text is no longer `${…}` and Treesitter can no longer
  re-find it for write-back; that path will need position-stable tracking
  (extmarks). Resolution-as-display (this ADR) sidesteps it by never mutating text.
