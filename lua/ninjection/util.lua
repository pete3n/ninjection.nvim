---@class ninjection.util
local M = {}
local cfg = {}
local lspconfig = require("lspconfig")

M.set_config = function(config)
	cfg = config
end

-- We need to provide a way of recording and restoring whitespace from the parent
-- buffer to allow easily formatting the buffer without worrying about its
-- relative placement in the parent buffer.

--- Return the whitespace borders in the current buffer.
--- @return table metadata A table containing:
---   - top_ws: number of blank lines at the top.
---   - bottom_ws: number of blank lines at the bottom.
---   - left_indent: minimum number of leading spaces on nonempty lines.
M.get_borders = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local top_ws = 0
  local bottom_ws = 0
  local left_indent = math.huge

  for _, line in ipairs(lines) do
    if line:match("^%s*$") then
      top_ws = top_ws + 1
    else
      break
    end
  end

  for i = #lines, 1, -1 do
    if lines[i]:match("^%s*$") then
      bottom_ws = bottom_ws + 1
    else
      break
    end
  end

  for _, line in ipairs(lines) do
    if not line:match("^%s*$") then
      local indent = line:match("^(%s*)")
      if indent then
        local count = #indent
        if count < left_indent then
          left_indent = count
        end
      end
    end
  end

  if left_indent == math.huge then
    left_indent = 0
  end

  return { top_ws = top_ws, bottom_ws = bottom_ws, left_indent = left_indent }
end

--- Restores the recorded whitespace borders (top, bottom, and left indent)
--- to a block of text.
---
--- The `borders` table should have the following structure:
---   {
---     top_ws = <number>,       -- Number of blank lines to add at the top.
---     bottom_ws = <number>,    -- Number of blank lines to add at the bottom.
---     left_indent = <number>   -- Number of spaces to prepend to each non-empty line.
---   }
---
--- @param text string|table The text to which borders should be restored.
---        Can be either a string (with newline separators) or a table of lines.
--- @param borders table The whitespace borders to restore.
--- @return table restored_lines A table of lines with the borders restored.
M.restore_borders = function(text, borders)
  -- Ensure we have a table of lines.
  local lines
  if type(text) == "string" then
    lines = vim.split(text, "\n")
  elseif type(text) == "table" then
    lines = text
  else
    error("restore_borders: text must be a string or a table of lines")
  end

  -- Create the indentation string.
  local indent = string.rep(" ", borders.left_indent or 0)

  -- Reapply left indent to each non-empty line.
  for i, line in ipairs(lines) do
    if line:match("%S") then
      lines[i] = indent .. line
    end
  end

  -- Prepend top blank lines.
  for i = 1, (borders.top_ws or 0) do
    table.insert(lines, 1, "")
  end

  -- Append bottom blank lines.
  for i = 1, (borders.bottom_ws or 0) do
    table.insert(lines, "")
  end

  return lines
end

--- Returns an adjusted "visual" range for a node,
--- approximating the range of text that is actually seen (as returned by get_node_text).
--- @param node TSNode The Treesitter node.
--- @param bufnr number The buffer number.
--- @return number visual_s_row, number visual_s_col, number visual_e_row, number visual_e_col
M.get_visual_range = function(node, bufnr)
  -- Get the raw range (0-indexed)
  local s_row, s_col, e_row, e_col = node:range()

  -- Get the raw lines from the buffer for the node
  local raw_lines = vim.api.nvim_buf_get_lines(bufnr, s_row, e_row + 1, false)
  -- Get the "visual" text as extracted by get_node_text()
  local visual_text = vim.treesitter.get_node_text(node, bufnr)
  local visual_lines = vim.split(visual_text, "\n", { plain = true })

  if #raw_lines == 0 or #visual_lines == 0 then
    return s_row, s_col, e_row, e_col
  end

  -- For the first line, find the offset of the visual text in the raw line.
  local raw_first = raw_lines[1]
  local visual_first = visual_lines[1]
  local offset_start = raw_first:find(visual_first, 1, true) or 1
  local visual_s_col = s_col + offset_start - 1

  -- For the last line, find the offset of the visual text in the raw line.
  local raw_last = raw_lines[#raw_lines]
  local visual_last = visual_lines[#visual_lines]
  local offset_end = raw_last:find(visual_last, 1, true) or 1
  local visual_e_col = s_col + offset_end + #visual_last - 1

  -- Return the adjusted range (still 0-indexed)
  return s_row, visual_s_col, e_row, visual_e_col
end

-- Autocommands don't trigger properly when creating and arbitrarily assigning
-- filetypes to buffers, so we need our on function to start the appropriate
-- LSP.

--- Start an appropriate LSP for the provided language
--- @param lang string The filetype of the injected language (e.g., "lua", "python").
--- @param root_dir string The root directory for the buffer (inherits parent's root).
--- @return table result A table containing:
---   - `status` (string): The LSP startup status. Possible values:
---     - `"unmapped"`: No LSP mapped for this language.
---     - `"unconfigured"`: No configuration found for the LSP.
---     - `"unavailable"`: The LSP command is not available.
---     - `"unsupported"`: The LSP does not support this language.
---     - `"failed_start"`: The LSP failed to start.
---     - `"started"`: The LSP started successfully.
---   - `client_id` (integer): The client ID of the started LSP (or -1 on failure).
M.start_lsp = function(lang, root_dir)
	local lang_lsp = cfg.lsp_map[lang]

	-- The injected langauge must be mapped to an LSP value
  if not lang_lsp then
		vim.notify(
			"ninjection WARNING: No LSP mapped to language: " .. lang .. " check your configuration.",
			vim.log.levels.WARN
		)
    return {"unmapped", -1}
  end

	-- The LSP must have an available configuration
	local lsp_def = lspconfig[lang_lsp]
	if not lsp_def.config_def or not lsp_def.config_def.default_config then
		vim.api.nvim_err_writeln(
			"ninjection ERROR: Could not find configuration for " .. lang_lsp ..
			". Ensure it is installed and properly configured for lspconfig."
		)
		return {"unconfigured", -1}
	end

	-- The LSP must be available to execute
	local lsp_cmd = lsp_def.config_def.default_config.cmd
	if not lsp_cmd then
		vim.api.nvim_err_writeln(
			"ninjection ERROR: Command found to execute " .. lang_lsp ..
			" ensure it is installed and available in your path."
		)
		return {"unavailable", -1}
	end

	-- The LSP must support our injected language
	if not vim.tbl_contains(lsp_def.config_def.default_config.filetypes, lang) then
		vim.api.nvim_err_writeln(
			"ninjection ERROR: " .. lang_lsp .. " does not support " ..
			lang .. " modify your configuration to an appropriate LSP."
		)
		return {"unsupported", -1}
	end

	local client_id = vim.lsp.start({
		name = lang_lsp,
		cmd = lsp_cmd,
		root_dir = root_dir,
	})

	if not client_id then
		vim.api.nvim_err_writeln(
			"ninjection ERROR: " .. lang_lsp ..
			" did not start correctly, check your language client log (default ~/.local/state/nvim/lsp.log) " ..
			"for more information."
		)
		return {"failed_start", -1}
	else
		return {"started", client_id}
	end
end

return M
