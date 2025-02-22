-- Including dependency types because I can't figure out how to get
-- Lua Language Server to recognize Treesitter types for our CI workflow

---@class Range2
---@field [1] integer start row
---@field [2] integer end row

---@class Range4
---@field [1] integer start row
---@field [2] integer start column
---@field [3] integer end row
---@field [4] integer end column

---@class Range6
---@field [1] integer start row
---@field [2] integer start column
---@field [3] integer start bytes
---@field [4] integer end row
---@field [5] integer end column
---@field [6] integer end bytes

---@alias Range Range2|Range4|Range6

---@class TSNode: userdata
---@field id fun(self: TSNode): string
---@field tree fun(self: TSNode): TSTree
---@field range fun(self: TSNode, include_bytes: false?): integer, integer, integer, integer
---@field range fun(self: TSNode, include_bytes: true): integer, integer, integer, integer, integer, integer
---@field start fun(self: TSNode): integer, integer, integer
---@field end_ fun(self: TSNode): integer, integer, integer
---@field type fun(self: TSNode): string
---@field symbol fun(self: TSNode): integer
---@field named fun(self: TSNode): boolean
---@field missing fun(self: TSNode): boolean
---@field extra fun(self: TSNode): boolean
---@field child_count fun(self: TSNode): integer
---@field named_child_count fun(self: TSNode): integer
---@field child fun(self: TSNode, index: integer): TSNode?
---@field named_child fun(self: TSNode, index: integer): TSNode?
---@field descendant_for_range fun(self: TSNode, start_row: integer, start_col: integer, end_row: integer, end_col: integer): TSNode?
---@field named_descendant_for_range fun(self: TSNode, start_row: integer, start_col: integer, end_row: integer, end_col: integer): TSNode?
---@field parent fun(self: TSNode): TSNode?
---@field next_sibling fun(self: TSNode): TSNode?
---@field prev_sibling fun(self: TSNode): TSNode?
---@field next_named_sibling fun(self: TSNode): TSNode?
---@field prev_named_sibling fun(self: TSNode): TSNode?
---@field named_children fun(self: TSNode): TSNode[]
---@field has_changes fun(self: TSNode): boolean
---@field has_error fun(self: TSNode): boolean
---@field sexpr fun(self: TSNode): string
---@field equal fun(self: TSNode, other: TSNode): boolean
---@field iter_children fun(self: TSNode): fun(): TSNode, string
---@field field fun(self: TSNode, name: string): TSNode[]
---@field byte_length fun(self: TSNode): integer

---@class vim.treesitter.QueryInfo
---List of (unique) capture names defined in query.
---@field captures string[]
---
---Contains information about predicates and directives.
---Key is pattern id, and value is list of predicates or directives defined in the pattern.
---A predicate or directive is a list of (integer|string); integer represents `capture_id`, and
---string represents (literal) arguments to predicate/directive. See |treesitter-predicates|
---and |treesitter-directives| for more details.
---@field patterns table<integer, (integer|string)[][]>

---@class TSQuery: userdata
---@field inspect fun(self: TSQuery): TSQueryInfo

---@class (exact) TSQueryInfo
---@field captures string[]
---@field patterns table<integer, (integer|string)[][]>

--- @class TSQueryMatch: userdata
--- @field captures fun(self: TSQueryMatch): table<integer,TSNode[]>

---@class vim.treesitter.query.TSMetadata
---@field range? Range
---@field conceal? string
---@field [integer] vim.treesitter.query.TSMetadata
---@field [string] integer|string

---@class vim.treesitter.Query
---@field lang string name of the language for this parser
---@field captures string[] list of (unique) capture names defined in query
---@field info vim.treesitter.QueryInfo contains information used in the query (e.g. captures, predicates, directives)
---@field query TSQuery userdata query object
---@field iter_captures fun(self: vim.treesitter.Query, node: TSNode, source: integer|string, start: integer, stop: integer): fun(end_line: integer?): id: integer, node: TSNode, metadata: vim.treesitter.query.TSMetadata, match: TSQueryMatch

---@class TSTree: userdata
---@field root fun(self: TSTree): TSNode
---@field edit fun(self: TSTree, _: integer, _: integer, _: integer, _: integer, _: integer, _: integer, _: integer, _: integer, _:integer)
---@field copy fun(self: TSTree): TSTree
---@field included_ranges fun(self: TSTree, include_bytes: true): Range6[]
---@field included_ranges fun(self: TSTree, include_bytes: false): Range4[]

---@alias TSLoggerCallback fun(logtype: 'parse'|'lex', msg: string)

---@alias TSCallbackName
---| 'changedtree'
---| 'bytes'
---| 'detach'
---| 'child_added'
---| 'child_removed'

---@alias TSCallbackNameOn
---| 'on_changedtree'
---| 'on_bytes'
---| 'on_detach'
---| 'on_child_added'
---| 'on_child_removed'

---@class TSParser: userdata
---@field parse fun(self: TSParser, tree: TSTree?, source: integer|string, include_bytes: boolean): TSTree, (Range4|Range6)[]
---@field reset fun(self: TSParser)
---@field included_ranges fun(self: TSParser, include_bytes: boolean?): integer[]
---@field set_included_ranges fun(self: TSParser, ranges: (Range6|TSNode)[])
---@field set_timeout fun(self: TSParser, timeout: integer)
---@field timeout fun(self: TSParser): integer
---@field _set_logger fun(self: TSParser, lex: boolean, parse: boolean, cb: TSLoggerCallback)
---@field _logger fun(self: TSParser): TSLoggerCallback

---@class vim.treesitter.LanguageTree
---@field private _callbacks table<TSCallbackName,function[]> Callback handlers
---@field package _callbacks_rec table<TSCallbackName,function[]> Callback handlers (recursive)
---@field private _children table<string,vim.treesitter.LanguageTree> Injected languages
---@field private _injection_query vim.treesitter.Query Queries defining injected languages
---@field private _injections_processed boolean
---@field private _opts table Options
---@field private _parser TSParser Parser for language
---@field private _has_regions boolean
---@field private _regions table<integer, Range6[]>?
---List of regions this tree should manage and parse. If nil then regions are
---taken from _trees. This is mostly a short-lived cache for included_regions()
---@field private _lang string Language name
---@field private _parent? vim.treesitter.LanguageTree Parent LanguageTree
---@field private _source (integer|string) Buffer or string to parse
---@field private _trees table<integer, TSTree> Reference to parsed tree (one for each language).
---Each key is the index of region, which is synced with _regions and _valid.
---@field private _valid boolean|table<integer,boolean> If the parsed tree is valid
---@field private _logger? fun(logtype: string, msg: string)
---@field private _logfile? file*
---@field parse fun(self: vim.treesitter.LanguageTree, range: boolean|Range|nil?): table: { [integer]: TSTree }
