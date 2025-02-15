---@class ninjection.util
local M = {}
local cfg = {}
local lspconfig = require("lspconfig")

M.set_config = function(config)
	cfg = config
end

-- Autocommands don't trigger properly when creating and arbitrarily assigning
-- filetypes to buffers, so we need our on function to start the appropriate
-- LSP.

--- @param lang string The filetype of the injected language (e.g., "lua", "python").
--- @param root_dir string The root directory for the buffer (inherits parent's root).
--- @return table result A table containing:
---   - `status` (string): The LSP startup status. Possible values:
---     - `"unmapped"`: No LSP mapped for this language.
---     - `"unconfigured"`: No configuration found for the LSP.
---     - `"unavailable"`: The LSP command is not available.
---     - `"unsupported"`: The LSP does not support this language.
---     - `"failed_start"`: The LSP failed to start.
---     - `"started"`: The LSP started successfully.
---   - `client_id` (integer): The client ID of the started LSP (or -1 on failure).
M.start_lsp = function(lang, root_dir)
	local lang_lsp = cfg.lsp_map[lang]

	-- The injected langauge must be mapped to an LSP value
  if not lang_lsp then
		vim.notify(
			"ninjection WARNING: No LSP mapped to language: " .. lang .. " check your configuration.",
			vim.log.levels.WARN
		)
    return {"unmapped", -1}
  end

	-- The LSP must have an available configuration
	local lsp_def = lspconfig[lang_lsp]
	if not lsp_def.config_def or not lsp_def.config_def.default_config then
		vim.api.nvim_err_writeln(
			"ninjection ERROR: Could not find configuration for " .. lang_lsp ..
			". Ensure it is installed and properly configured for lspconfig."
		)
		return {"unconfigured", -1}
	end

	-- The LSP must be available to execute
	local lsp_cmd = lsp_def.config_def.default_config.cmd
	if not lsp_cmd then
		vim.api.nvim_err_writeln(
			"ninjection ERROR: Command found to execute " .. lang_lsp ..
			" ensure it is installed and available in your path."
		)
		return {"unavailable", -1}
	end

	-- The LSP must support our injected language
	if not vim.tbl_contains(lsp_def.config_def.default_config.filetypes, lang) then
		vim.api.nvim_err_writeln(
			"ninjection ERROR: " .. lang_lsp .. " does not support " ..
			lang .. " modify your configuration to an appropriate LSP."
		)
		return {"unsupported", -1}
	end

	local client_id = vim.lsp.start({
		name = lang_lsp,
		cmd = lsp_cmd,
		root_dir = root_dir,
	})

	if not client_id then
		vim.api.nvim_err_writeln(
			"ninjection ERROR: " .. lang_lsp ..
			" did not start correctly, check your language client log (default ~/.local/state/nvim/lsp.log) " ..
			"for more information."
		)
		return {"failed_start", -1}
	else
		return {"started", client_id}
	end
end

return M
