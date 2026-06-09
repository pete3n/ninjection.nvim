# Treesitter is the sole mechanism for structural introspection

All structural understanding of code — locating injections, distinguishing a Nix
interpolation `${…}` from an escaped literal `''${…}`, identifying language
constructs — is obtained from Treesitter, never from regex or hand-rolled string
parsing. Ninjection is, in effect, a Treesitter plugin that extends Treesitter's
introspection into injected languages; re-implementing slices of a language's
lexer in Lua patterns would be fragile, would silently corrupt users' source,
and is explicitly out of scope to maintain.

## Consequences

- Stage 1 of the placeholder round-trip (see ADR-0001) takes the injected
  Treesitter node (or interpolation ranges precomputed from it), not a bare
  string, so it can rewrite by node range rather than by pattern match.
- Reverse (write-back) stays in the child buffer: the injected language's TS
  locates the variable nodes, and re-adding the parent's literal delimiter is a
  trivial prepend onto the TS-identified slice — no parent-language parsing and
  no buffer-language switch.
- The ban is on using string processing to *locate or parse* language structure.
  Once TS hands us a node range, a simple prepend/substitution on that slice (or
  matching ninjection's own fixed `>>> ninjection` fence marker) is not language
  parsing and remains acceptable. What is forbidden is scanning or parsing whole
  buffers / extracting language elements by hand.
