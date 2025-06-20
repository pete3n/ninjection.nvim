package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

describe("Plugin validation", function()
  local required_plugins = {
    { lib = "nvim-treesitter", optional = false, info = "Required for injected language parsing" },
    { lib = "conform", optional = true, info = "Optional for language formatting - must be configured" },
    { lib = "lspconfig", optional = true, info = "Optional for LSP configuration" },
  }

  local function is_installed(lib_name)
    local ok, _ = pcall(require, lib_name)
    return ok
  end

  for _, plugin in ipairs(required_plugins) do
    it("should have " .. plugin.lib .. " installed", function()
      local ok = is_installed(plugin.lib)
      if plugin.optional then
        if not ok then
          print("[INFO] Optional plugin missing: " .. plugin.lib .. " - " .. plugin.info)
        end
        assert.is_true(true) -- Always pass for optional plugins
      else
        assert.is_true(ok, "Required plugin missing: " .. plugin.lib .. " - " .. plugin.info)
      end
    end)
  end
end)
