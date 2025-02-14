local M = {}
local lspconfig = require("lspconfig")

M.check_lsp = function(ft)
  local mapped_lsp = require("ninjection").cfg.lsp_map[ft]
  if not mapped_lsp then
    print("No LSP configured for filetype: " .. ft)
    return "unavailable"
  end

  -- Check if LSP is already attached to any buffer
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client.name == mapped_lsp and client.attached_buffers[vim.api.nvim_get_current_buf()] then
      print("LSP " .. mapped_lsp .. " is already attached.")
      return "attached"
    end
  end

  -- Check if LSP is available in `lspconfig`
  if lspconfig[mapped_lsp] then
    print("LSP " .. mapped_lsp .. " is configured but not running.")
    return "configured"
  end

  -- If we reach here, the LSP is not available
  print("LSP " .. mapped_lsp .. " is unavailable.")
  return "unavailable"
end

M.start_lsp = function(ft)
  local mapped_lsp = require("ninjection").cfg.lsp_map[ft]
  if not mapped_lsp then
    print("No LSP mapped for filetype: " .. ft)
    return
  end

  local status = M.check_lsp(ft)
  if status == "attached" then
    print("LSP " .. mapped_lsp .. " is already running.")
    return
  elseif status == "unavailable" then
    print("LSP " .. mapped_lsp .. " is not available.")
    return
  end

  -- Start LSP if it's configured but not running
  if status == "configured" then
    print("Starting LSP: " .. mapped_lsp)
		lspconfig[mapped_lsp].setup({})
    vim.cmd("LspStart " .. mapped_lsp)

    -- Wait for LSP to start (we need to yield execution)
    vim.defer_fn(function()
      local clients = vim.lsp.get_clients()
      for _, client in ipairs(clients) do
        if client.name == mapped_lsp then
          print("LSP " .. mapped_lsp .. " started successfully.")
        end
      end
    end, 500)  -- Delay for 500ms to allow LSP startup
  end
end

return M
