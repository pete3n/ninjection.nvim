---@module "ninjection.config"
local M = {}

local vc = require("ninjection.health").validate_config

---@type Ninjection.Config
local default_config = {
	---@type string
	file_lang = "nix",
	---@type boolean
	preserve_indents = true,
	---@type  boolean
	auto_format = true,
	---@type string
	format_cmd = "_G.format_with_conform()",
	---@type integer
	injected_comment_lines = 1,
	---@type string
	register = "z",
	---@type boolean
	suppress_warnings = false,
	---@type EditorStyle
	editor_style = "floating",
	---@type table<string, string>
	inj_lang_queries = {
		nix = [[
						(
							(comment) @injection.language
							.
							[
								(indented_string_expression
									(string_fragment) @injection.content)
								(string_expression
									(string_fragment) @injection.content)
							]
							(#gsub! @injection.language "#%s*([%w%p]+)%s*" "%1")
							(#set! injection.combined)
						)
					]],
	},
	---@type string
	inj_lang_query = "",
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

local function merge_config()
	print("Merging user and default config")
	---@type Ninjection.Config
	local user_config = (type(vim.g.ninjection) == "function" and vim.g.ninjection() or vim.g.ninjection) or {}
	print("User config: " .. vim.inspect(user_config))
	---@type Ninjection.Config
	local config = vim.tbl_deep_extend("force", default_config, user_config)
	print("Merged config: " .. vim.inspect(config))

	local is_valid, err
	is_valid, err = vc(config)
	if not is_valid then
		error(err, 2)
	end

	print("Merged config (after validation): " .. vim.inspect(config))

	return config
end

function M.refresh()
	M.cfg = merge_config()
	print("Final config: " .. vim.inspect(M.cfg))
	return M.cfg
end

M.refresh()

return M
