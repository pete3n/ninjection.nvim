---@module "ninjection.health"
---@brief
--- The health module contains functions to validate configuration parameters
--- and check for required dependencies.
---
local health = require("vim.health")
local start = health.start
local ok = health.ok
local warn = health.warn
local h_error = health.error

local M = {}

---@tag ninjection.health.validate_config()
---@brief
---	Validates either a provided configuration table or the
---	current configuration.
---
--- Parameters ~
---@param cfg? Ninjection.Config
---
---@return boolean is_valid, string? err
---
M.validate_config = function(cfg)
	cfg = cfg or require("ninjection.config").values
	---@type boolean, string?
	local is_valid, err
	is_valid = true

	-- Ensure user only configures a supported editor style
	---@type table<boolean>
	local valid_editor_styles = { cur_win = true, floating = true, v_split = true, h_split = true }
	if not valid_editor_styles[cfg.editor_style] then
		err = "Ninjection configuration error: Invalid editor_style: " .. tostring(cfg.editor_style)
		is_valid = false
	end

	-- Ensure there is a Treesitter query available for the parent file language.
	if cfg.inj_lang_queries[cfg.file_lang] then
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
		h_error("Neovim 0.8 or greater required")
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
				h_error(lib_not_installed)
			end
		end
	end

	start("Checking configuration")
	local is_valid, err = M.validate_config()
	if is_valid then
		ok(" valid config.")
	elseif err then
		h_error(err)
	else
		h_error("Unknown error validating configuration.")
	end
end

return M
