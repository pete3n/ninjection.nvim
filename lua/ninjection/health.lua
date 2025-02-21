local health = require("vim.health")
local start = health.start
local ok = health.ok
local warn = health.warn
local error = health.warn

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
