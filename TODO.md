# Nix / Shell injected-language editing

Implemented (branch `feat/placeholder-roundtrip`):
- [x] Language header: shebang + fenced ninjection block of real declarations
- [x] Literal var placeholders: `''${var}` <-> `${var}`
- [x] Interpreted var placeholders: `${pkgs.var}` <-> `${pkgs_0x2Evar}`
      (in-place `_0x<HEX>` rename, restored via the block's `# <- host` arrows)

Follow-up:
- [ ] checkhealth: report the injected-language Treesitter grammar requirement
      for the placeholder round-trip (degrades gracefully today)
- [x] Resolve the `cfg.debug`-guarded string restorer in `replace()` — NOT inert:
      it re-adds the outer `''…'';` block delimiters and is load-bearing for every
      round-trip (the write-back range covers the whole injected node, delimiters
      included). The guard was a latent corruption bug — `debug=false` silently
      dropped the delimiters. Guard removed; `debug` now gates only diagnostics.
- [x] Delimiter model decided (ADR-0005 area): committed to the string
      modifier/restorer for the outer `''…'';`. Deleted the dead, never-wired
      `inj_lang_tweaks`/`parse_range_offset`/`buffer_cursor_offset` config + types
      (an abandoned range-exclusion design that had misled analysis). The inner
      escape/interp round-trip stays separate and Treesitter-based.
      (doc/ninjection.txt is generated; gendocs CI will drop the stale NJLangTweak
      entries on next run.)
- [ ] Bug: closing `'';` returns at the wrong indent on write-back for some
      indentation patterns (e.g. Python l_indent=6 -> 2 spaces instead of 4). In
      the restorer's `tab_indent = l_indent - tabstop` math. Pre-existing, not
      Python-specific.
- [ ] Real value interpolation for interpreted placeholders (default `""`/`nil` today)
      — deferred + documented in ADR-0005: needs extmark-based position tracking
      (Treesitter can't re-find a site whose text became the evaluated value, esp.
      inside a string). An interpolation is a tracked site + rendering policy.
      - [x] Feasibility spike: `resolve()` — display-only, non-destructive. Design
            settled in ADR-0006 + CONTEXT.md (Resolved value, Resolution scope).
            Implemented (`lua/ninjection/resolve.lua`, `tests/ft/nix/resolve/`):
            1. [~] Fixtures under `tests/ft/nix/resolve/` (unbound / `{pkgs}:` formal /
               `let`-bound). The eval root is the project flake for now; a *dedicated*
               pinned fixture flake is folded into the CI-seeding follow-up below.
            2. [x] `ninjection/resolve.lua`: `find_interpolation` + Treesitter
               scope-walk (`synthesize`) -> `builtins.getFlake "<root>"`-based `--expr`
               -> `nix eval --offline --impure --raw` -> `{ path }`. Lexical-first
               rule (Nix scoping: a lexical binding beats any `with`): `let` binding
               or `inherit (src) name;` -> reconstruct; function formal -> report
               `bound_by_caller`; lexically-unbound under `with` -> wrap in the with
               chain (let-bound env binding spliced ahead; unbound env head pulls the
               flake-pkgs preamble); otherwise-unbound -> supply `pkgs` from the flake.
               `with`/`inherit_from` landed 2026-06-10. Not handled yet: transitive
               deps of a reconstructed binding; plain `inherit name;` is passed over
               by design (it only re-binds the outer scope).
            3. [x] `ninjection.resolve()` verb in the `:Ninjection` dispatcher +
               `<Plug>(NinjectionResolve)`; renders via extmark `virt_text` (hover
               float remains a sibling renderer over the same engine).
            4. [x] Busted specs that skip cleanly (`pending`) when `nix`/nixpkgs-source
               is absent; the synthesis + `let`-eval specs run with no flake/network.
            - [x] Follow-up: engine eval is **async** — `resolve(node, bufnr,
                  root_dir, on_done)` is callback-only; `vim.system` on_exit delivers
                  via `vim.schedule`, never synchronously (even for `bound_by_caller`
                  and pre-eval errors, so callers see one contract). The verb renders
                  in the callback and returns immediately after dispatch
                  (`tests/ft/nix/resolve/resolve_async_spec.lua`).
            - [ ] Follow-up (scoped separately, NOT a spike blocker): a dedicated pinned
                  fixture flake + seeding its nixpkgs source into the ADR-0004 Docker
                  closure so the eval specs run offline in CI. The closure today carries
                  only the toolchain built from nixpkgs, not the source tree `nix eval`
                  reads, so the store-path specs `pending` in CI for now.
- [ ] Generalise beyond a Nix host / bash+sh injected languages
      - In progress: Python injected in Nix (parent stays Nix). Interpolation
        handling must become injected-keyed — shell rewrites `${x}`, Python leaves
        string-position interps verbatim (else the store path is corrupted).
      - Edge case (deferred): a Nix writer used as a bare top-level expression
        (`pkgs.writers.writePython3Bin "n" {...} ''...''`) isn't `;`-terminated
        like a `name = ... ;` binding; the round-trip range/restore logic assumes
        the assignment form. Workaround: wrap in `let x = <writer> ...; in { }`.
- [ ] Foldable ninjection block: wrap declarations in `{ ... }` with indentation
      so Neovim can fold/collapse a large header, e.g.
      `# >>> ninjection:nix` / `{` / `  var1=""` / `  ...` / `}` / `# <<< ninjection`
