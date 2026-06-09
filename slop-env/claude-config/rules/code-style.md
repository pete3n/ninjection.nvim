# Code style

Universal coding rules that apply to every project and language. These are
always in context (concatenated into CLAUDE.md), not relevance-recalled.

## Naming: clarity over brevity

Prefer clarity over brevity in variable names, and **never use single-letter
variable names** — including the common idioms of loop indices (`i`, `j`, `k`),
short element names (`e`), and sort/comparator parameters (`a`, `b`).

"If I really wanted brevity, I'd write assembly." Use descriptive names: `edit`
not `e`, `child` not `c`, `char` not `c`, `edit_a`/`edit_b` (or `lhs`/`rhs`) not
`a`/`b`, a meaningful index/element name not `i`.
