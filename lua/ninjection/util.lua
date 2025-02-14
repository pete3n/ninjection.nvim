local M = {}

M.get_available_lsp = function(ft)
  local active_clients = vim.lsp.get_clients()
  local available_lsp = {}

  -- Check active clients
  for _, client in ipairs(active_clients) do
    if client.config.filetypes and vim.tbl_contains(client.config.filetypes, ft) then
      table.insert(available_lsp, client)
    end
  end

  -- Check configured clients (from lspconfig)
  local lspconfig = require("lspconfig")
  for lsp_name, config in pairs(lspconfig) do
    if type(config) == "table" and config.filetypes and vim.tbl_contains(config.filetypes, ft) then
      table.insert(available_lsp, { name = lsp_name, config = config })
    end
  end

  return available_lsp
end

return M
