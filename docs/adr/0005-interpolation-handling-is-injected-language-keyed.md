# Interpolation handling is injected-language-keyed

Rewriting a parent interpolation into an editable placeholder is governed by the
**injected** language, not only the parent. The bash round-trip rewrites a Nix
`${expr}` to a safe identifier and restores it by finding an `expansion` node in
the child grammar (see ADR-0001/0002). That works only because of a *coincidence*:
Nix interpolation syntax `${x}` is identical to bash expansion syntax `${x}`, so
bash's Treesitter parses the site as an `expansion` even inside a string, and
reverse() can re-find it.

This does not generalise. Verified against Python's grammar:

- A Nix interpolation **inside a Python string** (`"${pkgs.gnugrep}/bin/grep"`,
  the canonical `writePython3Bin` shape) is inert `string_content` — valid, no
  diagnostic, and Treesitter exposes no node distinguishing it from ordinary text.
- A Nix interpolation **in code position** (`x = ${cfg.y}`) is a syntax error.

So the bash rewrite is actively harmful for Python: `forward()` rewriting the
string-position interpolation to `${pkgs_0x2E_gnugrep}` permanently corrupts the
store path, because `reverse()` (no `expansion` node in the Python grammar) cannot
undo it.

## Decision

Interpolation handling is keyed on the injected language. Shell-family injected
languages — whose grammar reads `${…}` as a live expansion — get the
rewrite-and-restore. Every other injected language passes interpolations through
**verbatim**: the interpolation is left in parent form and round-trips unchanged.
De-escaping a Nix literal escape (`''${x}`) in a non-shell injected language is
deferred on the same grounds (restore cannot re-find it). `forward()` therefore
takes the injected language (today it receives only the parent language) to select
the policy.

Python consequently rides the existing path shared with Lua — the outer-`''`
modifier/restorer plus dedent — and needs no shebang or ninjection block for the
canonical case, because nothing is declared.

Frame: an interpolation is a **tracked site with a rendering policy** — rewrite to
a safe identifier (shell), leave verbatim (non-shell), or, in future, substitute
the parent's real evaluated value.

## Consequences

- **Real-value resolution (deferred) is not foreclosed, but this is where it
  re-enters.** Substituting the parent's evaluated value replaces the child text
  entirely (a store path, not `${…}`), so restore can no longer locate the site
  via Treesitter — least of all inside a string, where TS never saw it. Real-value
  resolution will require position-stable tracking (extmarks placed at each
  interpolation site) rather than the current TS-based reverse. Passthrough today
  makes restore a trivial no-op; that is precisely the assumption real-value must
  revisit. Accepted: we document the path rather than build extmark tracking now.
- The placeholder token shape (`${name}` for shell vs. a bare identifier for a
  declared placeholder) and the placeholder node type (`expansion` vs.
  `identifier`) are properties of the injected language, not constants. They were
  hardcoded in `placeholder.lua`; generalising moves them onto the injected-keyed
  header descriptor.
- This sharpens ADR-0003. ADR-0003 says the child validates only its own language;
  this ADR adds that the round-trip *transform* is itself injected-keyed — a
  language ninjection does not recognise as `${}`-interpreting gets a verbatim
  pass, never a corrupting rewrite.
- The code-vs-string classification needed to handle code-position interpolations
  in non-shell languages (a future enhancement) is Treesitter-decidable — is the
  site inside a `string_content` node? — so it stays within ADR-0002.
