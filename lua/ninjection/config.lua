-- TODO: Implement language "helpers" for example:
-- Set filetype to sh for bash, set shebang if not set
--

---@module "ninjection.config"
---@brief
--- The config module contains the default ninjection configuration table and
--- functions to merge user config options and reload config changes.
---
local M = {}

local vc = require("ninjection.health").validate_config

---@nodoc
---@type Ninjection.Config
---@tag default_config
local default_config = {
	---@type boolean
	preserve_indents = true,
	---@type boolean
	auto_format = true,
	---@type string
	format_cmd = 'require("conform").format { async = true, lsp_format = "fallback" }',
	---@type string
	register = "z",
	---@type boolean
	debug = true,
	---@type EditorStyle
	editor_style = "floating",
	---@type vim.api.keyset.win_config
	win_config = {
		zindex = 25,
		style = "minimal",
		relative = "editor",
		width = math.floor(vim.o.columns * 0.8),
		height = math.floor(vim.o.lines * 0.8),
		row = math.floor((vim.o.lines - math.floor(vim.o.lines * 0.8)) / 2),
		col = math.floor((vim.o.columns - math.floor(vim.o.columns * 0.8)) / 2),
		border = "single",
	},
	---@type table<string, string>
	inj_lang_queries = {
		nix = [[
			(
				(comment) @injection.language . (indented_string_expression)
				@injection.content (#gsub! @injection.language "#%s*([%w%p]+)%s*" "%1")
				(#set! injection.combined)
			)
		]]
	},
	---@type table<string, NJLangTweak>
	inj_lang_tweaks = {
		---@type NJLangTweak
		nix = {
			---@type NJRange
			parse_range_offset = { s_row = 1, e_row = -1, s_col = 0, e_col = 0},
			---@type NJRange
			buffer_cursor_offset = { s_row = 1, e_row = -1, s_col = 0, e_col = 0},
		}
	},
	---@type table<string,string>
	lsp_map = {
		bash = "bashls",
		c = "clangd",
		cpp = "clangd",
		javascript = "ts_ls",
		json = "jsonls",
		lua = "lua_ls",
		python = "ruff",
		rust = "rust_analyzer",
		sh = "bashls",
		typescript = "ts_ls",
		yaml = "yamlls",
		zig = "zls",
	},
}

---@nodoc
--- Provide default_config for inspection, primarily for documentation.
---@return Ninjection.Config
M.get_default = function()
	return default_config
end

--- NOTE: width/height col/row default values are dynamically set to:
--- 80% of vim.o.columns/vim.o.rows and offset for a centered window.
---@eval return (function()
---  local s = vim.inspect(require("ninjection.config").get_default())
---  s = s:gsub("\\t", "  ")
---  s = s:gsub("\\n", "\n")
---  local lines = vim.split(s, "\n")
---  for i, line in ipairs(lines) do
---    lines[i] = "`" .. line   -- Prefix each line with a backtick.
---  end
---  return lines
--- end)()
---@minidoc_afterlines_end

---@tag config.reload()
---@brief
--- Reloads all ninjection modules to flush caches and apply a new config.
---
---@return nil
---
M.reload = function()
	for key in pairs(package.loaded) do
		if key:match("^ninjection") then
			package.loaded[key] = nil
		end
	end
end

---@nodoc
--- Merges user provided configuration overrides with the default configuration.
---@param cfg_overrides? Ninjection.Config
---@return nil
M._merge_config = function(cfg_overrides)
	---@type Ninjection.Config
	local user_config = vim.g.ninjection or cfg_overrides or {}
	---@type Ninjection.Config
	local config = vim.tbl_deep_extend("force", default_config, user_config)

	local is_valid, err
	is_valid, err = vc(config)
	if not is_valid then
		error(err, 2)
	end

	M.values = config
	return M.values
end

-- Provide default config in the event no user overrides are provided.
M.values = M._merge_config()
return M
