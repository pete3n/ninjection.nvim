local M = {}
local cfg = {}
local lspconfig = require("lspconfig")

M.set_config = function(config)
	cfg = config
end

-- Autocommands don't trigger properly when creating and arbitrarily assigning
-- filetypes to buffers, so we need our on function to start the appropriate
-- LSP.
M.start_lsp = function(lang, root_dir)
	local lang_lsp = nil

	-- There must be an LSP associated with the injected language
	for k, v in pairs(cfg.lsp_map) do
		if k == lang then
			lang_lsp = v
			break
		end
	end

  if not lang_lsp then
		vim.notify(
			"ninjeciton WARNING: No LSP configured for language: " .. lang .. " check your configuration.",
			vim.log.levels.WARN
		)
    return {"unavailable", -1}
  end

	-- The LSP must be available to execute
	local lsp_cmd = lspconfig[lang_lsp].lang_config.config_def.default_config.cmd
	if not lsp_cmd then
		vim.api.nvim_err_writeln(
			"ninjection ERROR: Command found to execute " .. lang_lsp ..
			" ensure it is installed and available in your path."
		)
		return {"unavailable", -1}
	end

	-- The LSP must support our injected language
	local lang_supported = false
	for _, v in ipairs(lspconfig[lang_lsp].lang_config.config_dev.default_config.filetypes) do
		if v == lang then
			lang_supported = true
		end
	end

	if not lang_supported then
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
		return {"start_error", -1}
	else
		return {"started", client_id}
	end
end

return M
