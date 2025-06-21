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
---@param cfg? NinjectionConfig
---
---@return boolean is_valid, string[]? err
---
M.validate_config = function(cfg)
	cfg = cfg or require("ninjection.config").values or {}

	---@type boolean, string[]
	local is_valid = true
	local errors = {}

	---@type table<boolean>
	local valid_editor_styles = { cur_win = true, floating = true, v_split = true, h_split = true }
	if not valid_editor_styles[cfg.editor_style] then
		table.insert(errors, "Invalid editor_style: " .. tostring(cfg.editor_style))
		is_valid = false
	end

	if cfg.format_cmd then
		---@type string[]
		local path = vim.split(cfg.format_cmd, ".", { plain = true })
		---@type unknown
		local fmt_fn = vim.tbl_get(_G, unpack(path))

		if type(fmt_fn) ~= "function" then
			---@cast fmt_fn function
			---@type boolean, string?
			local fn_ok, _ = pcall(function()
				vim.cmd("silent! " .. cfg.format_cmd)
			end)

			if not fn_ok then
				table.insert(
					errors,
					"Invalid format_cmd: '"
						.. cfg.format_cmd
						.. "' is neither a valid Lua function nor a valid Ex command"
				)
				is_valid = false
			end
		end
	end

	if is_valid then
		return true, nil
	else
		return false, errors
	end
end

-- TODO: Validate fmt_cmd
-- List all doublets configured
-- Check LSP executable
local required_plugins = {
	{ lib = "nvim-treesitter", optional = false, info = "Required for injected language parsing" },
}

local function lualib_installed(lib_name)
	local res, _ = pcall(require, lib_name)
	return res
end

function M.check()
	start("Checking Neovim version >= 0.11.0")
	if vim.version().major == 0 and vim.version().minor < 11 then
		h_error("Neovim 0.11.0 or greater required")
	else
		ok("Neovim >= 0.11.0 detected")
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
	local is_valid, errors = M.validate_config()

	if is_valid then
		ok("Valid config.")
	elseif errors then
		for _, msg in ipairs(errors) do
			h_error(msg)
		end
	else
		h_error("Unknown error validating configuration.")
	end
end

return M
