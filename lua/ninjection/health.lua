local health = require("vim.health")
local start = health.start or health.report_start -- Nvim 0.11 deprication
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.warn or health.report_error

local M = {}

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
end

return M
