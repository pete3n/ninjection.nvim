# Ninjection

Ninjection is a Treesitter plugin for Neovim that extends Treesitter's
introspection into injected languages: it makes injected-language code blocks
inside a parent file (e.g. shell or Lua embedded in Nix) editable as first-class
buffers — with the injected language's LSP, completion, and formatting — then
writes the edits back into the parent file. Structural understanding of code is
always Treesitter's job, never hand-rolled string parsing.

## Language

**Injection**:
A region of a parent file written in a different language, marked for Treesitter
to parse as that language. The unit ninjection extracts, edits, and writes back.
_Avoid_: snippet, embed, fragment

**Parent buffer**:
The buffer whose language contains the injections (e.g. the Nix file). Modeled as
`NJParent`. The model extends to grandchildren (a child buffer may itself open a
grandchild).
_Avoid_: host buffer, source buffer

**Child buffer**:
The ephemeral buffer holding a single injection's content in the injected
language, where editing happens. Modeled as `NJChild`.
_Avoid_: scratch buffer, edit buffer

**Injected language**:
The language of an injection's content and of the child buffer (e.g. bash).
Distinct from the parent buffer language.

**Language header**:
Ephemeral scaffolding prepended to a child buffer on edit and stripped on
write-back. Supplies what the injected language's LSP needs but the parent
(e.g. Nix) synthesizes at build time (e.g. a shell shebang), and carries a
delimited block recording the placeholder substitutions to reverse.

**Ninjection block**:
The delimited, comment-fenced region inside a language header holding real
variable declarations (initialized to the injected language's default value,
e.g. `""` for shell, `nil` for Lua) for the injected placeholders. Satisfies the
injected language's LSP (no undefined-variable diagnostics) and serves as the
round-trip ledger of which placeholders to restore — including rename mappings
for placeholders whose parent name is invalid in the injected language. Delimited
in the injected language's comment syntax; tagged with the parent buffer
language.

**Rename mapping**:
A ledger entry recording that an *interpreted* placeholder's parent name was
rewritten to an injected-language-safe identifier for editing (e.g. Nix
`pkgs.gnugrep` → `pkgs_0x2E_gnugrep`, since the dot is invalid in shell — each
invalid character is replaced in place by `_0x<HEX>_`).
Reversed on write-back. Only interpreted placeholders are renamed; literals never
are.

**Literal placeholder**:
A parent interpolation that denotes literal text rather than evaluation — in Nix,
`''${var}` produces the literal `${var}`. Ninjection de-escapes it to `${var}`
for editing and re-escapes on write-back. Literals are never renamed: the token
is its own injected-language name, so a literal whose name is invalid in the
injected language is left undeclared, letting that language's LSP surface the
pre-existing error rather than hiding it.
_Avoid_: escaped variable

**Interpreted placeholder**:
A parent interpolation the parent evaluates — in Nix, `${pkgs.hello}`. Whether
ninjection rewrites it for editing depends on the *injected* language: where the
injected language reads `${…}` as live syntax (shell expansion), it is rewritten
to an injected-language-safe identifier (see Rename mapping) and restored on
write-back; where `${…}` is inert in the injected language (e.g. inside a Python
string literal it is ordinary text), the interpolation is left verbatim and
round-trips unchanged. Substituting the parent's *real* evaluated value (rather
than a default) is a future enhancement (see Resolved value).

**Resolved value**:
The parent language's *actual evaluated* result for an interpolation — e.g. Nix
`${pkgs.hello}` resolves to its store path `/nix/store/…-hello`. The eventual
replacement for the placeholder default (`""`/`nil`) an interpreted placeholder
carries today (the deferred "real-value resolution" of ADR-0005). Produced by
`resolve()` and surfaced *non-destructively* — virtual text or a hover float —
never written into the buffer, preserving the round-trip's no-silent-mutation
discipline. For Nix, a store path is available at *evaluation* time, so resolving
never triggers a build.
_Avoid_: evaluated output, build result, eval result

**Resolution scope**:
The lexical bindings an interpolation needs to be evaluated on its own (what
`pkgs` is, etc.), recovered by Treesitter walking outward from the interpolation
node and synthesized into a self-contained expression. When the binding chain
bottoms out inside the file the interpolation is *self-contained* and resolvable;
when it ends in a **free variable** — a function parameter (`{ pkgs, lib }:`)
whose value is supplied by an unseen caller — it is not resolvable from the file
alone. This self-contained / free-variable boundary is the defining feasibility
limit of resolution.
_Avoid_: environment, context, binding set
