---@class NJRange
---@field s_row integer
---@field s_col integer
---@field e_row integer
---@field e_col integer

---@class NJNodeTable
---@field node TSNode
---@field range NJRange

---@class NJIndents
---@field t_indent number
---@field b_indent number
---@field l_indent number

---@class NJParent
---@field children integer[]

---@class NJChild
---@field bufnr integer
---@field root_dir string
---@field parent_bufnr integer
---@field parent_indents NJIndents
---@field parent_range NJRange

---@class NJLspStatus
---@field status string -- The LSP startup status. Possible values: "unmapped",
--- "unconfigured", "unavailable", "no-exec", "unsupported", "failed_start", "started"
---@field client_id integer -- The client ID of the started LSP, or -1 on failure

---@alias BufferStyle "std" | "popup" | "v_split" | "h_split" | "tab_r" | "tab_l"
