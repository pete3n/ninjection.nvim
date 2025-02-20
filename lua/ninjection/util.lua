---@class ninjection.util
local M = {}
local cfg = {}
require("ninjection.types")
local lspconfig = require("lspconfig")

M.set_config = function(config)
	cfg = config
end

-- We need to provide a way of recording and restoring whitespace from the parent
-- buffer to allow easily formatting the buffer without worrying about its
-- relative placement in the parent buffer.

---Function: Find whitespace indents (top, bottom, left) in the provided buffer.
---@param bufnr integer  Buffer handle
---@return NJIndents|nil table Stores indentation values
---@return nil|string err Error string, if applicable
--- Return, on success, A table containing:
---  - t_indent: number of blank lines at the top.
---  - b_indent: number of blank lines at the bottom.
---  - l_indent: minimum number of leading spaces on nonempty lines.
--- Return, on failure, nil and error string, if applicable
M.get_indents = function(bufnr)
	---@type boolean, any|nil, string[]|nil
	local ok, raw_output, lines

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	lines = raw_output
	if not lines or #lines == 0 then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.util.get_indents() warning: No lines returned " ..
			"from calling vim.api.nvim_buf_get_lines()", vim.log.levels.WARN)
		end
	end
	---@cast lines string[]

	---@type NJIndents
  local indents = { t_indent = 0, b_indent = 0, l_indent = math.huge }

  for _, line in ipairs(lines) do
		---@cast line string
    if line:match("^%s*$") then
			indents.t_indent = indents.t_indent + 1
    else
      break
    end
  end

  for i = #lines, 1, -1 do
		---@cast i number
    if lines[i]:match("^%s*$") then
      indents.b_indent = indents.b_indent + 1
    else
      break
    end
  end

	for _, line in ipairs(lines) do
		---@cast line string
		if not line:match("^%s*$") then
			---@type string|nil
			local indent = line:match("^(%s*)")
			if indent then
				-- Use vim.fn.strdisplaywidth() to calculate the visible width of the indent,
				-- which will account for tabs.
				local count = vim.fn.strdisplaywidth(indent)
				if count < indents.l_indent then
					indents.l_indent = count
				end
			end
		end
	end

  if indents.l_indent == math.huge then
    indents.l_indent = 0
  end

  return indents, nil
end


--- Restores the recorded whitespace indents (top, bottom, and left indent)
--- to a block of text.
---
--- @param text string|table The text for which indents should be restored.
--- Can be either a string (with newline separators) or a table of lines.
--- @param indents NJIndents  Table with indent values for t, b, l
--- @return table|nil restored_lines  A table of lines with the indents restored.
--- @return nil|string err  Error message, if applicable
M.restore_indents = function(text, indents)
	---@type boolean, any|nil, string|nil, table|nil
  local ok, raw_output, err, lines

  if type(text) == "string" then
		ok, raw_output = pcall(function()
			return vim.split(text, "\n")
		end)
		if not ok then
			error(tostring(raw_output),2)
		end
    lines = raw_output
		if not lines then
			if cfg.suppress_warnings == false then
				vim.notify("ninjection.util.restore_indents() warning: No lines " ..
					"returned from calling vim.split()", vim.log.levels.WARN)
			end
			return nil
		end
  elseif type(text) == "table" then
    lines = text
  else
		error("ninjection.util.restore_indents() error: Text must be a string or "
			.. "a table of lines", 2)
  end
	---@cast lines table

  -- Create the left indentation string.
	---@type string
  local l_indent = string.rep(" ", indents.l_indent or 0)

  -- Only apply the left indent to non-blank lines
  for i, line in ipairs(lines) do
		---@cast i number
		---@cast line string
    if line:match("%S") then
      lines[i] = l_indent .. line
    end
  end

  -- Prepend top indent lines.
  for _ = 1, (indents.t_indent or 0) do
    table.insert(lines, 1, "")
  end

  -- Append bottom indent lines.
  for _ = 1, (indents.b_indent or 0) do
		if cfg.preserve_indents then
			-- Compute the left indent string, subtracting one tab size.
			local tab_size = vim.o.tabstop or 8
			-- Ensure the resulting indent length is not negative.
			local adjusted_indent = string.rep(" ", math.max(0,
				(indents.l_indent or 0) - tab_size))
			table.insert(lines, adjusted_indent)
		else
			table.insert(lines, "")
		end
  end

  return lines
end

-- Autocommands don't trigger properly when creating and arbitrarily assigning
-- filetypes to buffers, so we need a function to start the appropriate LSP.

--- Start an appropriate LSP for the provided language
--- @param lang string The filetype of the injected language (e.g., "lua", "python").
--- @param root_dir string The root directory for the buffer.
--- @return NJLspStatus|nil result  A table containing the LSP status and client_id
--- Return: "unmapped", "unconfigured", "unavailable", "no-exec", "unsupported",
--- "failed_start", "started" and client_id if available
--- @return nil|string err Error message, if applicable
M.start_lsp = function(lang, root_dir)
	---@type boolean, any|nil, string|nil, string|nil
	local ok, raw_output, err, lang_lsp

	-- The injected langauge must be mapped to an LSP value
	lang_lsp = cfg.lsp_map[lang]
  if not lang_lsp then
		vim.notify("ninjection.util.start_lsp() warning: No LSP mapped to " ..
			"language: " .. lang .. " check your configuration.", vim.log.levels.WARN)
    return {"unmapped", -1}
  end
	---@cast lang_lsp string

	-- The LSP must have an available configuration
	ok, raw_output = pcall(function()
		return lspconfig[lang_lsp]
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	---@type table|nil
	local lsp_def = raw_output
	if not lsp_def or not lsp_def.config_def then
		vim.notify("ninjection.util.start_lsp() warning: Could not find " ..
			"default_config for " .. lang_lsp .. ". Ensure it is installed and " ..
			"properly configured for lspconfig.", vim.log.levels.WARN)
		return {"unconfigured", -1}
	end
	---@cast lsp_def table

	-- The LSP binary path must exist
	---@type table|nil
	local lsp_cmd = lsp_def.cmd
	if not lsp_cmd or #lsp_cmd == 0 then
		vim.notify("ninjection.util.start_lsp() warning: Command to execute " .. lang_lsp ..
			" does not exist. Ensure it is installed and configured.", vim.log.levels.WARN)
		return {"unavailable", -1}
	end
	---@cast lsp_cmd table

	-- The LSP binary path must be executable
	ok, raw_output = pcall(function()
		return vim.fn.executable(lsp_cmd[1])
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	if raw_output ~= 1 then
		vim.notify("ninjection.util.start_lsp() warning: The LSP command: " ..
			lsp_cmd[1] .. " is not executable.", vim.log.levels.WARN)
		return {"no-exec", -1}
	end

	-- The LSP must support our injected language
	if not vim.tbl_contains(lsp_def.config_def.default_config.filetypes, lang) then
		vim.notify("ninjection.util.start_lsp() warning: The configured LSP: " ..
			lang_lsp .. " does not support " .. lang .. " modify your configuration " ..
			" to use an appropriate LSP.", vim.log.levels.WARN)
		return {"unsupported", -1}
	end

	ok, raw_output = pcall(function()
		return vim.lsp.start({
			name = lang_lsp,
			cmd = lsp_cmd,
			root_dir = root_dir,
		})
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	---@type integer|nil
	local client_id = raw_output
	if client_id == nil then
		vim.notify("ninjection.util.start_lsp() warning: The LSP: " .. lang_lsp ..
			" did not return a client_id, check your language client logs " ..
			"(default ~/.local/state/nvim/lsp.log) for more information.",
			vim.log.levels.WARN)
		return {"failed_start", -1}
	end
	---@cast client_id integer

	return {"started", client_id}
end

return M
