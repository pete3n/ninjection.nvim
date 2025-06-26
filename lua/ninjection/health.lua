---@module "ninjection.health"
---@brief
--- The health module contains functions to validate configuration parameters
--- and check for required dependencies.
---
local health = require("vim.health")
local start = health.start
local info = health.info
local ok = health.ok
local warn = health.warn
local h_error = health.error

local required_plugins = {
	{ lib = "nvim-treesitter", optional = false, info = "Required for injected language parsing" },
}

local M = {}

---@private
---@return NinjectionConfig
local function _get_cfg()
	return require("ninjection.config").values or {}
end

---@private
---@param lib_name string
---@return boolean resolved
local function _lualib_installed(lib_name)
	local resolved, _ = pcall(require, lib_name)
	return resolved
end

---@private
--- Flatten table for error message outputs.
---@param str_table table
---@return string[] flattened_tbl
local function _flatten_table(str_table)
	local flattened_tbl = {}

	local function flatten(val)
		if type(val) == "table" then
			for _, v in ipairs(val) do
				flatten(v)
			end
		else
			table.insert(flattened_tbl, tostring(val))
		end
	end

	flatten(str_table)
	return flattened_tbl
end

---@private
--- Ensure win_config uses a valid vim.api.keyset.win_config table.
---@return boolean is_valid, string[]? errors
local function _validate_win_config(cfg)
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
		table.insert(errors, validate_err)
		return false, _flatten_table(errors)
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

	cfg = cfg or require("ninjection.config").values or {}
	if #errors > 0 then
		return false, errors
	end

	return true, nil
end

---@private
--- Validate configured mapping between languages and LSPs
---@param lsp_map table<string, string>
---@return table<{lsp: string, is_valid: boolean, err: string?}> valid_lsp_map
local function _validate_lsp_map(lsp_map)
	lsp_map = lsp_map or {}
	---@type table<{lsp: string, is_valid: boolean, err: string?}>
	local valid_lsp_map = {}

	---@private
	---@param lsp_cmd unknown
	---@return boolean is_exec, string? err
	local function is_executable(lsp_cmd)
		if type(lsp_cmd) == "function" then
			return false, "Dynamic RPC clients are not supported"
		elseif type(lsp_cmd) == "table" and type(lsp_cmd[1]) == "string" then
			if vim.fn.executable(lsp_cmd[1]) == 1 then
				return true, nil
			else
				return false, "Executable not found in $PATH: " .. lsp_cmd[1]
			end
		end
		return false, "Unsupported cmd type: " .. type(lsp_cmd)
	end

	---@type table<string, boolean>
	local checked_lsp = {}

	---@type string
	for _, lsp in pairs(lsp_map) do
		if not checked_lsp[lsp] then
			checked_lsp[lsp] = true
			---@type vim.lsp.ClientConfig?
			local lsp_cfg = vim.lsp.config[lsp]
			if not lsp_cfg then
				table.insert(valid_lsp_map, { lsp = lsp, is_valid = false, err = "No config found" })
			else
				local is_exec, exec_err = is_executable(lsp_cfg.cmd)
				table.insert(valid_lsp_map, {
					lsp = lsp,
					is_valid = is_exec,
					err = is_exec and nil or exec_err,
				})
			end
		end
	end

	return valid_lsp_map
end

---@private
---@param cfg NinjectionConfig
local function _print_lang_pair_table(cfg)
	local inj_lang_queries = cfg.inj_lang_queries or {}
	local lsp_map = cfg.lsp_map or {}

	local filetypes = vim.tbl_keys(inj_lang_queries)
	table.sort(filetypes)

	local injected_langs = vim.tbl_keys(lsp_map)
	table.sort(injected_langs)

	if #filetypes == 0 or #injected_langs == 0 then
		warn("No configured injected languages or filetypes found.")
		return
	end

	local col_widths = {}
	col_widths[1] = math.max(11, unpack(vim.tbl_map(vim.fn.strdisplaywidth, injected_langs))) + 2
	for i, ft in ipairs(filetypes) do
		col_widths[i + 1] = math.max(#ft, 1) + 2
	end

	local function pad_str(str, len)
		local pad_len = len - vim.fn.strdisplaywidth(str)
		return str .. string.rep(" ", math.max(0, pad_len))
	end

	-- Header row
	local header_cells = { pad_str("Injections", col_widths[1]) }
	for i, ft in ipairs(filetypes) do
		table.insert(header_cells, pad_str(ft, col_widths[i + 1]))
	end
	info(table.concat(header_cells, ""))

	-- Data rows
	for _, inj_lang in ipairs(injected_langs) do
		local row_cells = { pad_str(inj_lang, col_widths[1]) }
		for i, outer_ft in ipairs(filetypes) do
			local is_supported = inj_lang_queries[outer_ft] and lsp_map[inj_lang]
			table.insert(row_cells, pad_str(is_supported and "✓" or "", col_widths[i + 1]))
		end
		info(table.concat(row_cells, ""))
	end
end

---@private
---@param delimiters table<string, NJDelimiterPair>
---@return boolean is_valid, string[]? errors
local function _validate_format_delimiters(delimiters)
	---@type string[]
	local errors = {}
	if type(delimiters) == "table" then
		for k, v in pairs(delimiters) do
			---@type unknown
			local val = v
			if type(val) ~= "table" then
				table.insert(errors, "`format_delimiters[" .. k .. "]` must be a table")
				return false, errors
			else
				---@type string|unknown
				local start_delim = val["open"]
				---@type string|unknown
				local end_delim = val["close"]

				if type(start_delim) ~= "string" or type(end_delim) ~= "string" then
					table.insert(errors, "`format_delimiters[" .. k .. "]` must have string 'open' and 'close' keys.")
					return false, errors
				end
			end
		end
	else
		table.insert(errors, "`format_delimiters` must be a table.")
		return false, errors
	end

	return true, nil
end

---@private
---@param formatter unknown
---@return boolean is_valid, string[]? errors
local function _validate_formatter(formatter)
	---@type string[]
	local errors = {}
	if type(formatter) == "function" then
		---@cast formatter function
		---@type boolean, string?
		local fn_call_ok, fn_call_err = pcall(formatter)
		if not fn_call_ok then
			table.insert(errors, "Invalid anonymous function: \n'" .. formatter .. "'\n'" .. fn_call_err .. "'")
			return false, errors
		end
	elseif type(formatter) == "string" then
		---@cast formatter string
		---@type unknown
		local global_fn = _G[formatter]
		if type(global_fn) == "function" then
			---@cast global_fn function
			---@type boolean, string?
			local fmt_ok, fmt_err = pcall(global_fn)
			if not fmt_ok then
				table.insert(errors, "Invalid formatting global function: \n'" .. formatter .. "'\n'" .. fmt_err .. "'")
				return false, errors
			end
		else
			---@type boolean, string?
			local cmd_ok, cmd_err = pcall(function()
				vim.cmd(formatter)
			end)
			if not cmd_ok then
				table.insert(
					errors,
					"Invalid formatter user defined command: \n'"
						.. formatter
						.. "' is not a valid Ex command: \n"
						.. cmd_err
				)
				return false, errors
			end
		end
	end

	return true, nil
end

---@private
---@param text_modifiers table<string, NJTextModifier>
---@return boolean is_valid, string[]? errors
local function _validate_text_modifiers(text_modifiers)
	---@type boolean
	local is_valid = true
	---@type string[]
	local errors = {}

	if type(text_modifiers) == "table" then
		for k, fn in pairs(text_modifiers) do
			if type(fn) ~= "function" then
				table.insert(errors, "`inj_text_modifiers[" .. k .. "]` must be a function")
				is_valid = false
			else
				---@type boolean, string, table<string, boolean>
				local mod_call_ok, mod_result_str, mod_result_meta = pcall(fn, "test text")
				if not mod_call_ok then
					table.insert(
						errors,
						"`inj_text_modifiers[" .. k .. "]` errored during test call: " .. tostring(mod_result_str)
					)
					is_valid = false
				elseif type(mod_result_str) ~= "string" then
					table.insert(errors, "`inj_text_modifiers[" .. k .. "]` must return a string as the first result")
					return false, errors
				elseif type(mod_result_meta) ~= "table" then
					table.insert(errors, "`inj_text_modifiers[" .. k .. "]` must return a table as the second result")
					is_valid = false
				else
					for meta_k, meta_v in pairs(mod_result_meta) do
						if type(meta_k) ~= "string" or type(meta_v) ~= "boolean" then
							table.insert(
								errors,
								"`inj_text_modifiers[" .. k .. "]` must return table<string, boolean> as second result"
							)
							is_valid = false
						end
					end
				end
			end
		end
	end

	if is_valid then
		return true, nil
	else
		return false, errors
	end
end

---@private
---@param text_restorers table<string, NJTextRestorer>
---@return boolean is_valid, string[]? errors
local function _validate_text_restorers(text_restorers)
	---@type boolean
	local is_valid = true

	---@type string[]
	local errors = {}

	if type(text_restorers) == "table" then
		for k, fn in pairs(text_restorers) do
			if type(fn) ~= "function" then
				table.insert(errors, "`inj_text_restorers[" .. k .. "]` must be a function")
				is_valid = false
			else
				---@type boolean, any
				local res_call_ok, res_result_str = pcall(fn, "test text", { dummy = true })

				if not res_call_ok then
					table.insert(
						errors,
						"`inj_text_restorers[" .. k .. "]` errored during test call: " .. tostring(res_result_str)
					)
					is_valid = false
				elseif type(res_result_str) ~= "table" then
					table.insert(errors, "`inj_text_restorers[" .. k .. "]` must return a table of strings")
					is_valid = false
				else
					for i, val in ipairs(res_result_str) do
						if type(val) ~= "string" then
							table.insert(
								errors,
								"`inj_text_restorers["
									.. k
									.. "]` must return table<string>, but value at index "
									.. i
									.. " is of type "
									.. type(val)
							)
							is_valid = false
							break
						end
					end
				end
			end
		end
	end

	if is_valid then
		return true, nil
	else
		return false, errors
	end
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
function M.validate_config(cfg)
	cfg = cfg or _get_cfg()
	---@type boolean, string[]
	local is_valid = true
	local errors = {}

	---@type table<boolean>
	local valid_editor_styles = { cur_win = true, floating = true, v_split = true, h_split = true }
	if not valid_editor_styles[cfg.editor_style] then
		table.insert(errors, "Invalid editor_style: " .. tostring(cfg.editor_style))
		is_valid = false
	end

	if cfg.formatter then
		---@type boolean, string[]?
		local fmtr_ok, fmtr_errs = _validate_formatter(cfg.formatter)
		if not fmtr_ok then
			table.insert(errors, fmtr_errs)
			is_valid = false
		end
	end

	if cfg.inj_text_modifiers then
		---@type boolean, string[]?
		local mod_ok, mod_errs = _validate_text_modifiers(cfg.inj_text_modifiers)
		if not mod_ok then
			table.insert(errors, mod_errs)
			is_valid = false
		end
	end

	if cfg.inj_text_restorers then
		---@type boolean, string[]?
		local res_ok, res_errs = _validate_text_restorers(cfg.inj_text_restorers)
		if not res_ok then
			table.insert(errors, res_errs)
			is_valid = false
		end
	end

	---@type boolean, string[]?
	local win_ok, win_errs = _validate_win_config(cfg.win_config)
	if not win_ok then
		table.insert(errors, win_errs)
		is_valid = false
	end

	if not cfg.format_delimiters then
		is_valid = false
		table.insert(errors, "`format_delimiters` must be configured.")
	else
		---@type boolean, string[]?
		local delim_ok, delim_err = _validate_format_delimiters(cfg.format_delimiters)
		if not delim_ok then
			table.insert(errors, delim_err)
			is_valid = false
		end
	end

	if is_valid then
		return true, nil
	else
		return false, _flatten_table(errors)
	end
end

---@tag ninjection.health.check()
---@brief
--- checkhealth function for ninjection: checks requirements and
--- validates configuration.
---
function M.check()
	local cfg = _get_cfg()
	start("Checking Neovim version >= 0.11.0")
	if vim.version().major == 0 and vim.version().minor < 11 then
		h_error("Neovim 0.11.0 or greater required")
	else
		ok("Neovim >= 0.11.0 detected")
	end

	start("Checking for required plugins")
	for _, plugin in ipairs(required_plugins) do
		if _lualib_installed(plugin.lib) then
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
	local is_valid, errors = M.validate_config(cfg)
	if is_valid then
		ok("valid config.")
	elseif errors then
		for _, msg in ipairs(errors) do
			h_error(msg)
		end
	else
		h_error("Unknown error validating configuration.")
	end

	start("Checking configured LSPs")
	for _, result in ipairs(_validate_lsp_map(cfg.lsp_map)) do
		if result.is_valid then
			ok(result.lsp .. " is available.")
		else
			h_error(result.lsp .. " is invalid: " .. (result.err or "unknown error"))
		end
	end

	start("Checking configured language pairs")
	_print_lang_pair_table(cfg)
end

return M
