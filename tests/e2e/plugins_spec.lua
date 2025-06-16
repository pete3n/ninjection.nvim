package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

describe("Required plugins", function()
  local required_plugins = {
    { lib = "nvim-treesitter", optional = false, info = "Required for injected language parsing" },
  }

  local function is_installed(lib_name)
    local ok, _ = pcall(require, lib_name)
    return ok
  end

  for _, plugin in ipairs(required_plugins) do
    it("should have " .. plugin.lib .. " installed", function()
      local ok = is_installed(plugin.lib)
      if plugin.optional then
        -- optional plugins can be missing but we warn
        if not ok then
          print("[WARN] Optional plugin missing: " .. plugin.lib .. " - " .. plugin.info)
        end
        assert.is_true(true) -- Always pass for optional plugins
      else
        assert.is_true(ok, "Required plugin missing: " .. plugin.lib .. " - " .. plugin.info)
      end
    end)
  end
end)
