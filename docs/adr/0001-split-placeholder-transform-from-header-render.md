# Split placeholder transform (host-keyed) from header render (injected-keyed)

Making injected code editable spans two independent language axes: rewriting
host interpolations into editable placeholders is governed by the **parent
buffer language's** rules (e.g. Nix decides that `''${x}` is a literal and
`${pkgs.y}` is an interpolation), while building the language header — shebang,
comment delimiter, assignment operator, default value — is governed by the
**injected (child) language's** rules (bash `#`/`=`/`""` vs Lua `--`/` = `/`nil`).

We model these as two stages rather than one function: a parent-keyed *transform*
that returns `(body, ledger)`, then an injected-keyed *header renderer* that turns
the ledger into header text prepended to the child buffer. Restore runs them in
reverse. We chose this over a single function told both languages because it
matches the codebase's existing grain (parent-keyed tables like
`inj_text_modifiers` beside injected-keyed tables like `lsp_map`), keeps each
unit single-responsibility and independently testable, and makes adding an
injected language a matter of supplying a header descriptor rather than editing
the Nix transform.

## Consequences

- The in-buffer ninjection block *is* the ledger, so placeholder data is parsed
  back out of the child buffer on restore rather than threaded through
  `text_meta`.
- Header height is needed only transiently during `edit()` (to offset the child
  cursor by the prepended header) and is passed into `set_cursor`; it is *not*
  stored in `text_meta`, and restore locates the header by fence-scan, not a
  stored count.
- `text_meta` is therefore not for ninjection's internal bookkeeping. Its purpose
  is to be an accessible per-language round-trip channel that a user's modifier
  writes and that user's restorer reads, with core shuttling it opaquely — the
  extension point for adding language behavior without core changes. It should be
  typed opaquely (`table<string, any>`), not narrowed to `table<string, boolean>`.
