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
