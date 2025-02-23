---@meta

---@alias EditorStyle "cur_win" | "floating" | "v_split" | "h_split"
-- Modified from nvim-lspconfig/lua/lspconfig/configs.lua because I can't find
-- a reference to: vim.api.keyset.create_user_command.command_args
---@alias lspconfig.Config.command {[1]:string|vim.api.keyset.user_command}

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
---@field p_bufnr integer
---@field p_indents NJIndents
---@field p_range NJRange

---@class NJLspStatus
---@field status string -- The LSP startup status. Possible values: "unmapped",
--- "unconfigured", "unavailable", "no-exec", "unsupported", "failed_start", "started"
---@field client_id integer -- The client ID of the started LSP, or -1 on failure

-- Helper annotation for lspconfig from nvim-lspconfig/lua/lspconfig/configs.lua
--- @class lspconfig.Config : vim.lsp.ClientConfig
--- @field enabled? boolean
--- @field single_file_support? boolean
--- @field silent? boolean
--- @field filetypes? string[]
--- @field filetype? string
--- @field on_new_config? fun(new_config: lspconfig.Config?, new_root_dir: string)
--- @field autostart? boolean
--- @field package _on_attach? fun(client: vim.lsp.Client, bufnr: integer)
--- @field root_dir? string|fun(filename: string, bufnr: number)
--- @field commands? table<string, lspconfig.Config.command>
