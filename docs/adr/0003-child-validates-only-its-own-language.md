# The child buffer validates only its own language

The child buffer is responsible for being valid in the injected language, using
that language's Treesitter grammar and LSP. It is *not* responsible for
validating the text it writes back into the parent buffer. If a user edits a
placeholder into something invalid for the parent language, the parent's own
Treesitter grammar / LSP reports the error after write-back and the user
re-edits there.

We chose this boundary rather than having ninjection re-validate the round-tripped
result against the parent language, because each buffer already has first-class
tooling for its own language and duplicating parent validation inside the child
edit flow adds complexity for no gain — the parent buffer surfaces the error
exactly where the user fixes it.

## Consequences

- Substituting the parent's *real* evaluated value into placeholders (real-time
  interpolation in the child buffer) is out of scope for now; placeholders are
  declared with the injected language's default value (`""`, `nil`).
- The round-trip's correctness obligation is limited to reproducing the user's
  intent (escape vs. bare interpolation), not to guaranteeing the result is valid
  parent-language code.
- Literals are never renamed. A literal's editable token *is* its
  injected-language name, so a literal with an injected-invalid name (`''${cfg.foo}`,
  which already emitted invalid shell) is de-escaped but left undeclared — the
  injected LSP surfaces the pre-existing error instead of ninjection hiding it
  behind a rename. Consequently only interpreted placeholders carry a ledger
  arrow, and the reverse rule is: arrow → bare `${p_var}`; otherwise
  (bare-in-block or absent) → escape `''${c_var}`.
