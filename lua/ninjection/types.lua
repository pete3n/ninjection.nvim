---@class NJRange
---@field s_row integer
---@field s_col integer
---@field e_row integer
---@field e_col integer

---@class NJCursor
---@field row integer
---@field col integer

---@class NJNodeTable
---@field node TSNode
---@field range NJRange

---@class NJIndents
---@field t_indent number
---@field b_indent number
---@field l_indent number

---@class NJParent
---@field bufnr integer
---@field root_dir string
---@field cursor NJCursor
---@field indents NJIndents
---@field mode string
---@field range NJRange

---@class NJChild
---@field parent NJParent

---@class NJLspStatus
---@field status string -- The LSP startup status. Possible values: "unmapped",
--- "unconfigured", "unavailable", "no-exec", "unsupported", "failed_start", "started"
---@field client_id integer -- The client ID of the started LSP, or -1 on failure

