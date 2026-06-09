# Nix / Shell injected-language editing

Implemented (branch `feat/placeholder-roundtrip`):
- [x] Language header: shebang + fenced ninjection block of real declarations
- [x] Literal var placeholders: `''${var}` <-> `${var}`
- [x] Interpreted var placeholders: `${pkgs.var}` <-> `${pkgs_0x2Evar}`
      (in-place `_0x<HEX>` rename, restored via the block's `# <- host` arrows)

Follow-up:
- [ ] checkhealth: report the injected-language Treesitter grammar requirement
      for the placeholder round-trip (degrades gracefully today)
- [ ] Resolve the `cfg.debug`-guarded string restorer in `replace()` — currently
      inert and accidentally load-bearing (see docs/adr/0001 notes / memory)
- [ ] Real value interpolation for interpreted placeholders (default `""`/`nil` today)
- [ ] Generalise beyond a Nix host / bash+sh injected languages
- [ ] Foldable ninjection block: wrap declarations in `{ ... }` with indentation
      so Neovim can fold/collapse a large header, e.g.
      `# >>> ninjection:nix` / `{` / `  var1=""` / `  ...` / `}` / `# <<< ninjection`
