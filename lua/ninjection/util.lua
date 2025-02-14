local M = {}
local cfg = {}
local lspconfig = require("lspconfig")

M.set_config = function(config)
	cfg = config
end

M.check_lsp = function(ft)
  local mapped_lsp = cfg.lsp_map[ft]
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

M.attach_lsp = function(ft, bufnr, root_dir)
  local mapped_lsp = cfg.lsp_map[ft]

  if not mapped_lsp then
    print("No LSP mapped for filetype: " .. ft)
    return nil
  end

  local status = M.check_lsp(ft)
  if status == "attached" then
    print("LSP " .. mapped_lsp .. " is already attached.")
    return nil
  elseif status == "unavailable" then
    print("LSP " .. mapped_lsp .. " is not available.")
    return nil
  end

  if status == "configured" then
    print("Starting LSP: " .. mapped_lsp .. " with root_dir: " .. root_dir)

    -- Ensure LSP is set up with the correct root directory
    if not lspconfig[mapped_lsp].manager then
      print("LSP " .. mapped_lsp .. " not initialized, setting up...")
      lspconfig[mapped_lsp].setup({
        root_dir = root_dir,  -- Pass the root directory
      })
    end

    -- Try attaching the LSP manually
    local success = lspconfig[mapped_lsp].manager.try_add(bufnr)
    if success then
      print("LSP " .. mapped_lsp .. " attached successfully to buffer " .. bufnr)
    else
      print("Failed to attach LSP " .. mapped_lsp .. " to buffer " .. bufnr)
    end
  end
end

return M
