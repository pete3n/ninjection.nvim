local M = {}
local cfg = {}
local lspconfig = require("lspconfig")

M.set_config = function(config)
	cfg = config
end

M.start_lsp = function(lang, bufnr, root_dir)
	local lang_lsp = nil

	-- There must be an LSP associated with the injected language
	for k, v in pairs(cfg.lsp_map) do
		if k == lang then
			lang_lsp = v
			break
		end
	end

  if not lang_lsp then
    print("No LSP configured for language: " .. lang)
    return "unavailable"
  end

	local lang_config = lspconfig[lang_lsp]
	print(vim.inspect(lang_config))

	local default_config = lang_config.config_def.default_config
	print(vim.inspect(default_config))

	local cmd = lang_config.config_def.default_config.cmd
	print("LSP command:", vim.inspect(cmd))
end

return M
