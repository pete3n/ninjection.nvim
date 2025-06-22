vim.api.nvim_create_user_command("NinjectionSetup", function()
  vim.ui.input({
    prompt = "Enter Lua config table (e.g. { formatter = function() ... end }):",
    default = "{ }",
  }, function(input)
    if not input then
      vim.notify("NinjectionSetup cancelled", vim.log.levels.WARN)
      return
    end

    local chunk, err = load("return " .. input)
    if not chunk then
      vim.notify("Failed to parse config: " .. err, vim.log.levels.ERROR)
      return
    end

    local ok, user_cfg = pcall(chunk)
    if not ok then
      vim.notify("Error evaluating config: " .. user_cfg, vim.log.levels.ERROR)
      return
    end

    -- Save for reload purposes
    _G.ninjection_config = user_cfg

    -- Call reload to invalidate module cache
    require("ninjection.config").reload()

    -- Re-require and run setup with fresh modules
    require("ninjection").setup(_G.ninjection_config)

    vim.notify("Ninjection configured and reloaded.", vim.log.levels.INFO)
  end)
end, {
  desc = "Prompt and run ninjection.setup() with Lua table config override",
})

-- Invalidate all modules and re-setup from _G.ninjection_config
vim.api.nvim_create_user_command("NinjectionReload", function()
	local cfg = _G.ninjection_config or vim.g.ninjection or {}
	require("ninjection.config").reload()
	require("ninjection").setup(cfg)
	vim.notify("Ninjection modules reloaded.", vim.log.levels.INFO)
end, {
	desc = "Reload all ninjection modules",
})

-- Validate the current effective config
vim.api.nvim_create_user_command("NinjectionValidate", function()
	local cfg = require("ninjection.config").values
	local is_valid, errors = require("ninjection.health").validate_config(cfg)
	if is_valid then
		vim.notify("Ninjection configuration is valid.", vim.log.levels.INFO)
	else
		vim.notify("Ninjection configuration errors:\n" .. table.concat(errors or {}, "\n"), vim.log.levels.ERROR)
	end
end, {
	desc = "Validate ninjection configuration",
})

vim.api.nvim_create_user_command("NinjectionPrintConfig", function()
	local cfg = require("ninjection.config").values
	vim.notify(vim.inspect(cfg), vim.log.levels.INFO)
end, {
	desc = "Print the current ninjection.config.values",
})
