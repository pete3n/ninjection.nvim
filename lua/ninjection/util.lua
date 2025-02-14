local M = {}

M.get_available_lsp = function(ft)
  local active_clients = vim.lsp.get_clients()
  local available_lsp = {}

  -- Debugging: Log expected filetype
  print("Looking for LSP matching filetype: " .. vim.inspect(ft))

  -- Normalize filetype: Trim whitespace & lowercase (just in case)
  ft = ft:match("^%s*(.-)%s*$") -- Trim spaces
  ft = ft:lower() -- Convert to lowercase (some LSPs might be case-sensitive)

  -- Check active clients
  for _, client in ipairs(active_clients) do
    if client.config.filetypes then
      for _, client_ft in ipairs(client.config.filetypes) do
        if client_ft:lower() == ft then
          print("Active LSP found: " .. client.name .. " (matches " .. client_ft .. ")")
          table.insert(available_lsp, client)
        end
      end
    end
  end

  -- Check configured clients (from lspconfig)
  local lspconfig = require("lspconfig")
  for lsp_name, config in pairs(lspconfig) do
    if type(config) == "table" and config.filetypes then
      for _, client_ft in ipairs(config.filetypes) do
        if client_ft:lower() == ft then
          print("Configured LSP found: " .. lsp_name .. " (matches " .. client_ft .. ")")
          table.insert(available_lsp, { name = lsp_name, config = config })
        end
      end
    end
  end

  -- Debugging: Print found LSPs
  print("Available LSPs: " .. vim.inspect(available_lsp))
  return available_lsp
end

return M
