---@module "ninjection.health"

local health = require("vim.health")
local config = require("ninjection.config").cfg
local start = health.start
local ok = health.ok
local warn = health.warn
local error = health.warn

local M = {}

---@return boolean, string|nil
M.validate_config = function(cfg)
	cfg = cfg or config
	local err, is_valid
	is_valid = true

	local valid_editor_styles = { cur_win = true, floating = true, v_split = true, h_split = true }
	if not valid_editor_styles[cfg.editor_style] then
		err = "Ninjection configuration error: Invalid editor_style: " .. tostring(cfg.editor_style)
		is_valid = false
	end

	if not vim.tbl_contains(cfg.lsp_map, cfg.file_lang) then
		err =	"Ninjection configuration error: " .. cfg.file_lang ..
			" has not associated LSP configured in lsp_map property."
		is_valid = false
	end

	if cfg.inj_lang_queries[cfg.file_lang] then
		---@type string
		cfg.inj_lang_query = cfg.inj_lang_queries[cfg.file_lang]
	else
		err = "Ninjection: No injection query found for file_lang " .. cfg.file_lang
	end

	return is_valid, err
end

local required_plugins = {
	{ lib = "lspconfig", optional = false, info = "Required for LSP integration" },
	{ lib = "nvim-treesitter", optional = false, info = "Required for injected language parsing" },
}

local function lualib_installed(lib_name)
	local res, _ = pcall(require, lib_name)
	return res
end

function M.check()
	start("Checking Neovim version >= 0.8")
	if vim.version().major == 0 and vim.version().minor < 8 then
		error("Neovim 0.8 or greater required")
	else
		ok("Neovim >= 0.8 detected")
	end

	start("Checking for required plugins")
	for _, plugin in ipairs(required_plugins) do
		if lualib_installed(plugin.lib) then
			ok(plugin.lib .. " installed.")
		else
			local lib_not_installed = plugin.lib .. " not found."
			if plugin.optional then
				warn(("%s %s"):format(lib_not_installed, plugin.info))
			else
				error(lib_not_installed)
			end
		end
	end

	start("Checking configuration")
		local is_valid, err = validate_config()
		if is_valid then
			ok(" valid config.")
		elseif err then
			warn (err)
		else
			warn ("Unknown error validating configuration.")
		end

end

return M
