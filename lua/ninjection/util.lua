local M = {}

M.get_available_lsp = function(ft)
  local active_clients = vim.lsp.get_clients()
  local available_lsp = {}

  print("Checking active LSP clients...")  -- Debugging
  print(vim.inspect(active_clients))  -- See if any clients exist

  -- Check active clients
  for _, client in ipairs(active_clients) do
    print("Checking client: " .. client.name)  -- Debugging
    if client.config.filetypes and vim.tbl_contains(client.config.filetypes, ft) then
      table.insert(available_lsp, client)
    end
  end

  print("Checking configured LSPs...")  -- Debugging
  local lspconfig = require("lspconfig")
  for lsp_name, config in pairs(lspconfig) do
    if type(config) == "table" and config.filetypes and vim.tbl_contains(config.filetypes, ft) then
      print("Configured LSP found: " .. lsp_name)  -- Debugging
      table.insert(available_lsp, { name = lsp_name, config = config })
    end
  end

  print("Available LSPs: " .. vim.inspect(available_lsp))  -- Debugging
  return available_lsp
end

return M
