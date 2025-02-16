--- Treesitter helper functions for ninjection
---@class ninjection.treesitter
local M = {}
local cfg = {}

local ts = require("vim.treesitter")

M.set_config = function(config)
	cfg = config
end

--- Gets a parsed query from Treesitter given a language and Grammar
---@param query string  Lua-literal string for Treesitter query
---@return vim.treesitter.Query|nil parsed_query  The Treesitter parsed Query object
---@return nil|string err  Error string on failure
M.get_query = function(query)
	---@type boolean, TSQuery
	local ok, parsed_query, raw_output
	ok, raw_output = pcall(ts.query.parse("nix", query))

	if not ok then
		---@type string
		local err = tostring(raw_output)
		vim.notify("ninjection.treesitter.get_query(): Failed.")
		return nil, err
	end

	parsed_query = raw_output
	return parsed_query, nil
end

--- Function: Identify the injected language block at the current cursor position
--- with start and ending coordinates.
---
---@param query string  Lua-literal string query to identify an injected
---@param bufnr integer  buffer handle to query (must be in current window)
---
---@return { node: TSNode, range: Range4, lang: string|nil, err: string|nil }|nil table
--- Return: On success, a table containing:
--- node: TSNode - the Treesitter node element (see :h TSNode)
--- range: Range4 - s_col, s_row, e_col, e_row integer coordinates for the node
--- NOTE: Coordinates may not match the actual text locations (see the
--- get_visual_range function for this).
--- lang: string|nil - the parsed language comment, if identifiable
--- err: string|nil - language parsing error, if exists
---
--- Return: On failure: nil, err string if available
---@return nil|string err Error string on failure if it exists
M.get_node_info = function(query, bufnr)
	---@type integer[]
	local cursor = vim.api.nvim_win_get_cursor(0) -- current window cursor position
	---@type integer
	local cur_row = cursor[1] - 1 --convert to 0-indexed
	---@type integer
	local cur_col = cursor[2]

	--- @type vim.treesitter.Query|nil, string|nil
	local parsed_query, err = M.get_query(query)
	if not parsed_query then
		vim.notify("ninjection.treesitter.get_node_info(): parse_query() failed")
		return nil, err
	end

	--- @type boolean, vim.treesitter.LanguageTree
	local ok, parser_trees, raw_output
	ok, raw_output = pcall(function()
		return ts.get_parser(bufnr, "nix")
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.treesitter.get_node_info(): get_parser() failed")
		return nil, err
	end
	parser_trees = raw_output

	---@type TSTree
	---@const
	local tree = parser_trees:parse()[1]

	---@type TSNode
	local root
	root = tree:root()

	-- We only want to work with injected language content that the cursor is
	-- currently located in, so we need to search for the injected.content string
	-- in our Treesitter capture and determine if our cursor is inside its range.
	for id, node, _, _ in parsed_query:iter_captures(root, bufnr, 0, -1) do
		---@cast id integer
		---@cast node TSNode
		---@type string
		local capture_name = parsed_query.captures[id]
		---@type string|nil
		local lang

		if capture_name == "injection.content" then
			---@type integer
			local s_row, s_col, e_row, e_col = node:range()
			---@type Range4
			local inj_range = { s_row, s_col, e_row, e_col }
			---@type Range4
			local cur_point = { cur_row, cur_col, cur_row, cur_col }

			if ts.node_contains(node, cur_point) then
				-- We identified an injected language at our cursor location
				-- We need to parse the language string, assuming the language comment
				-- is entirely above the injected code.
				lang, err = M.get_inj_lang(node, bufnr)
			end
			return { node, inj_range, lang, err }
		end
	end

	err = "ninjection.treesitter.get_node_info(): no injection.content id found in node."
	return nil, err
end

--- Parse an injected content node for a language comment
---@param node TSNode Treesitter node containing the text to parse for a language
--- comment
---@param bufnr integer  Buffer handle for the node parent buffer
---@return string|nil lang  Parsed language comment
---@return nil|string err  Error string
M.get_inj_lang = function(node, bufnr)
	---@type boolean, string
	local ok, lang, raw_output
	ok, raw_output = pcall(function()
		return ts.get_node_text(node, bufnr)
	end)

	if not ok then
		---@type string
		local err = tostring(raw_output)
		vim.notify("ninjection.treesitter.get_inj_lang(): get_node_text() failed.")
		return nil, err
	end
	-- Gross regex magic
	raw_output = raw_output:gsub("^%s*(.-)%s*$", "%1")
	raw_output = raw_output:gsub("^#%s*", "")

	lang = raw_output

	-- Check language against table of languages mapped to LSPs
	if lang and cfg.lsp_map[lang] then
		return lang, nil
	end

	---@type string
	local err
	err = "ninjection.treesitter.get_inj.lang(): no supported injected languages were found." ..
		" parsed: " .. lang
	return nil, err
end

-- Treesitter's selection for "injected.content" doesn't match the actual text
-- that is selected. We need a function that adjusts the selection to match.

--- Returns an adjusted "visual" range for a node,
--- approximating the range of text that is actually seen (as returned by get_node_text).
--- @param node TSNode The Treesitter node.
--- @param bufnr number The buffer number.
--- @return number visual_s_row, number visual_s_col, number visual_e_row, number visual_e_col
M.get_visual_range = function(node, bufnr)
  local s_row, s_col, e_row, e_col = node:range()
  local raw_lines = vim.api.nvim_buf_get_lines(bufnr, s_row, e_row, false)
  local visual_text = ts.get_node_text(node, bufnr)
  local visual_lines = vim.vim.split(visual_text, "\n", { plain = true })

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

  return s_row, visual_s_col, e_row, visual_e_col
end

return M
