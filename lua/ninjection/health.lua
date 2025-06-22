---@module "ninjection.health"
---@brief
--- The health module contains functions to validate configuration parameters
--- and check for required dependencies.
---
local health = require("vim.health")
local start = health.start
local ok = health.ok
local warn = health.warn
local h_error = health.error

local M = {}

---@nodoc
--- Ensure win_config uses a valid vim.api.keyset.win_config table.
---@return boolean succes, string[]? errors
local function validate_win_config(cfg)
	---@type string[]
	local errors = {}

	---@type boolean, string?
	local valid_cfg, validate_err = pcall(function()
		vim.validate({
			row = { cfg.row, "number", true },
			col = { cfg.col, "number", true },
			width = { cfg.width, "number", true },
			height = { cfg.height, "number", true },
			anchor = { cfg.anchor, { "string", "nil" } },
			relative = { cfg.relative, { "string", "nil" } },
			split = { cfg.split, { "string", "nil" } },
			win = { cfg.win, { "number", "nil" } },
			bufpos = { cfg.bufpos, { "table", "nil" } },
			external = { cfg.external, { "boolean", "nil" } },
			focusable = { cfg.focusable, { "boolean", "nil" } },
			mouse = { cfg.mouse, { "boolean", "nil" } },
			vertical = { cfg.vertical, { "boolean", "nil" } },
			zindex = { cfg.zindex, { "number", "nil" } },
			border = { cfg.border, { "string", "table", "nil" } },
			title_pos = { cfg.title_pos, { "string", "nil" } },
			footer_pos = { cfg.footer_pos, { "string", "nil" } },
			style = { cfg.style, { "string", "nil" } },
			noautocmd = { cfg.noautocmd, { "boolean", "nil" } },
			fixed = { cfg.fixed, { "boolean", "nil" } },
			hide = { cfg.hide, { "boolean", "nil" } },
		})
	end)

	if not valid_cfg then
		table.insert(errors, vim.inspect(validate_err))
		return false, errors
	end

	local enums = {
		anchor = { NW = true, NE = true, SW = true, SE = true },
		relative = { cursor = true, editor = true, laststatus = true, mouse = true, tabline = true, win = true },
		split = { left = true, right = true, above = true, below = true },
		title_pos = { center = true, left = true, right = true },
		footer_pos = { center = true, left = true, right = true },
		style = { minimal = true },
	}

	local border_enums = {
		none = true,
		single = true,
		double = true,
		rounded = true,
		solid = true,
		shadow = true,
	}

	for field, allowed in pairs(enums) do
		local val = cfg[field]
		if val and not allowed[val] then
			table.insert(errors, "`win_config." .. field .. "` has invalid value: " .. tostring(val))
		end
	end

	-- Handle border specially because it can be a table of strings or a single string
	local border = cfg.border
	if border and type(border) == "string" then
		if not border_enums[border] then
			table.insert(errors, "`win_config.border` has invalid value: " .. border)
		end
	elseif type(border) == "table" then
		for i, v in ipairs(border) do
			if type(v) ~= "string" or not border_enums[v] then
				table.insert(errors, "`win_config.border[" .. i .. "]` has invalid value: " .. tostring(v))
			end
		end
	end

	if #errors > 0 then
		return false, errors
	end

	return true, nil
end

---@tag ninjection.health.validate_config()
---@brief
---	Validates either a provided configuration table or the
---	current configuration.
---
--- Parameters ~
---@param cfg? NinjectionConfig
---
---@return boolean is_valid, string[]? err
---
M.validate_config = function(cfg)
	cfg = cfg or require("ninjection.config").values or {}

	---@type boolean, string[]
	local is_valid = true
	local errors = {}

	---@type table<boolean>
	local valid_editor_styles = { cur_win = true, floating = true, v_split = true, h_split = true }
	if not valid_editor_styles[cfg.editor_style] then
		table.insert(errors, "Invalid editor_style: " .. tostring(cfg.editor_style))
		is_valid = false
	end

	if cfg.format_cmd then
		---@type unknown
		local fmt_fn = _G[cfg.format_cmd]

		if type(fmt_fn) ~= "function" then
			---@cast fmt_fn string
			---@type boolean, string?
			local cmd_ok, cmd_err = pcall(function()
				vim.cmd(cfg.format_cmd)
			end)

			if not cmd_ok then
				table.insert(
					errors,
					"Invalid format_cmd: '"
						.. cfg.format_cmd
						.. "' is not a Lua function and is not a valid Ex command: "
						.. cmd_err
				)
				is_valid = false
			end
		end
	end

	---@type boolean, string[]?
	local win_ok, win_errs = validate_win_config(cfg.win_config)
	if not win_ok then
		table.insert(errors, win_errs)
		is_valid = false
	end

	if is_valid then
		return true, nil
	else
		return false, errors
	end
end

-- TODO: Validate fmt_cmd
-- List all doublets configured
-- Check LSP executable
local required_plugins = {
	{ lib = "nvim-treesitter", optional = false, info = "Required for injected language parsing" },
}

local function lualib_installed(lib_name)
	local res, _ = pcall(require, lib_name)
	return res
end

function M.check()
	start("Checking Neovim version >= 0.11.0")
	if vim.version().major == 0 and vim.version().minor < 11 then
		h_error("Neovim 0.11.0 or greater required")
	else
		ok("Neovim >= 0.11.0 detected")
	end

	start("Checking for required plugins")
	for _, plugin in ipairs(required_plugins) do
		if lualib_installed(plugin.lib) then
			ok(plugin.lib .. " installed.")
		else
			local lib_not_installed = plugin.lib .. " not found."
			if plugin.optional then
				warn(("%s %s"):format(lib_not_installed, plugin.info))
			else
				h_error(lib_not_installed)
			end
		end
	end

	start("Checking configuration")
	local is_valid, errors = M.validate_config()

	if is_valid then
		ok("Valid config.")
	elseif errors then
		for _, msg in ipairs(errors) do
			h_error(msg)
		end
	else
		h_error("Unknown error validating configuration.")
	end
end

return M
