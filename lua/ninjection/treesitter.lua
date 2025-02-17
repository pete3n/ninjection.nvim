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
	ok, raw_output = pcall(function()
		return ts.query.parse("nix", query)
	end)
	if not ok then
		---@type string
		local err = tostring(raw_output)
		vim.notify("ninjection.treesitter.get_query(): Failed.", vim.log.levels.WARN)
		return nil, err
	end
	parsed_query = raw_output

	return parsed_query, nil
end

--- Function: Helper function to parse the root tree from a Treesitter Query
---@param bufnr integer  Buffer handle
---@return TSNode|nil root  root node of TSTree for language syntax
---@return nil|string err  error string if available
M.get_root = function (bufnr)
	---@type boolean, vim.treesitter.LanguageTree, string
	local ok, parser, err, raw_output
  ok, raw_output = pcall(function()
		return vim.treesitter.get_parser(bufnr, "nix")
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.treesitter.get_root(): " ..
			"Error calling vim.treesitter.get_parser()", vim.log.levels.WARN)
		return nil, err
	end
	parser = raw_output
  if not parser then
    vim.notify("ninjection.treesitter.get_root(): No parser available for nix!",
			vim.log.levels.WARN)
    return nil, "ninjection.treesitter.get_root(): No parser available for nix!"
  end
	---@type TSTree
  local tree = parser:parse()[1]
  if not tree then
    vim.notify("ninjection.treesitter.get.root(): No syntax tree found!", vim.log.levels.WARN)
    return nil, "ninjection.treesitter.get.root(): No syntax tree found!"
  end
  return tree:root(), nil
end

--- Function: Identify the injected language node at the current cursor position
--- with start and ending coordinates.
---
---@param query string  Lua-literal string query to identify an injected
---@param bufnr integer  buffer handle to query (must be in current window)
---
---@return { node: TSNode, range: Range4 }|nil table
--- Return, on success, a table containing:
--- node: TSNode - the Treesitter node element (see :h TSNode)
--- range: Range4 - s_col, s_row, e_col, e_row integer coordinates for the node
--- NOTE: Coordinates may not match the actual text locations (see the
--- get_visual_range function for this).
---
--- Return, on failure: nil, err string if available
---@return nil|string err Error string on failure if it exists
M.get_node_table = function(query, bufnr)
	---@type integer[]
	local cursor = vim.api.nvim_win_get_cursor(0) -- current window cursor position
	---@type integer
	local cur_row = cursor[1] - 1 --convert to 0-indexed
	---@type integer
	local cur_col = cursor[2]

	--- @type vim.treesitter.Query|nil, string|nil
	local parsed_query, err = M.get_query(query)
	if not parsed_query then
		vim.notify("ninjection.treesitter.get_node_info(): Could not parse " ..
			"the Treesitter query with get_query().",
			vim.log.levels.WARN)
		if err then
			vim.notify("ninjection.treesitter.get_node_info(): Error calling get_query()",
				vim.log.levels.WARN)
		end
		return nil, err
	end

	---@type TSNode|nil
	local root
	root, err = M.get_root(bufnr)
	if not root then
			vim.notify("ninjection.treesitter.get_node_table(): Could not determine " ..
				"the syntax tree root from get_root().", vim.log.levels.WARN)
		if err then
			vim.notify("ninjection.treesitter.get_node_table(): Error calling get_root()",
				vim.log.levels.WARN)
		end
		return nil, err
	end

	for id, node, _, _ in parsed_query:iter_captures(root, bufnr, 0, -1) do
		---@cast id integer
		---@cast node TSNode
		---@type string
		local capture_name = parsed_query.captures[id]

		if capture_name == "injection.content" then
			---@type integer
			local s_row, s_col, e_row, e_col = node:range()
			---@type Range4
			local inj_range = { s_row, s_col, e_row, e_col }
			---@type Range4
			local cur_point = { cur_row, cur_col, cur_row, cur_col }

			if ts.node_contains(node, cur_point) then
				return { node = node, range = inj_range }
			end
		end
	end

	vim.notify("ninjection.treesitter.get_node_table(): No injection.content id" ..
		"found in node.", vim.log.levels.WARN)
	return nil, nil
end

--- Parse an injected content node for a language comment
---@param query string  Lua-literal string query to identify an injected
---@param bufnr integer  Buffer handle for the node parent buffer
---@return string|nil lang  Parsed language comment
---@return nil|string err  Error string
M.get_inj_lang = function(query, bufnr)
	--- @type vim.treesitter.Query|nil, string|nil
	local parsed_query, err = M.get_query(query)
	if not parsed_query then
		vim.notify("ninjection.treesitter.get_inj_lang(): Could not parse " ..
			"the Treesitter query with get_query().", vim.log.levels.WARN)
		if err then
			vim.notify("ninjection.treesitter.get_inj_lang(): Error calling get_query()",
			vim.log.levels.WARN)
		end
		return nil, err
	end

	---@type TSNode|nil
	local root
	root, err = M.get_root(bufnr)
	if not root then
			vim.notify("ninjection.treesitter.get_inj_lang(): Could not determine " ..
				"the syntax tree root from get_root().", vim.log.levels.WARN)
		if err then
			vim.notify("ninjection.treesitter.get_inj_lang(): Error calling get_root()",
				vim.log.levels.WARN)
		end
		return nil, err
	end

	---@type table|nil
	local node_info
  node_info, err = M.get_node_table(cfg.inj_lang_query, bufnr)
  if not node_info then
		vim.notify("ninjection.treesitter.get_inj_lang(): Could not determine " ..
			"injected content calling get_node_table()",
			vim.log.levels.WARN)
		if err then
			vim.notify("ninjection.treesitter.get_ing_lang(): Error calling " ..
				"get_node_table()", vim.log.levels.WARN)
		end
		return nil, err
  end

	---@type integer
	local node_s_row = node_info.range[1]
	if not node_s_row then
		err = "ninjection.treesitter.get_inj_lang(): Could not determine " ..
			"inject language starting row calling get_node_table()"
		return nil, err
	end

	---@type table|nil
	local candidate_node
  for id, node, _ in parsed_query:iter_captures(root, bufnr, 0, -1) do
		---@cast id, integer
		---@cast node, TSNode
    local capture_name = parsed_query.captures[id]
    if capture_name == "injection.language" then
			---@type integer
      local e_row = select(3, node:range())
      -- Assuming the language comment is entirely above the injection block.
      if e_row < node_s_row then
        if not candidate_node or (e_row > candidate_node.e_row) then
          candidate_node = { node = node, e_row = e_row }
        end
      end
    end
  end

  if candidate_node then
		---@type boolean, string
    local ok, candidate_text, raw_output
		ok, raw_output = pcall(function()
			return vim.treesitter.get_node_text(candidate_node.node, bufnr)
		end)
		if not ok then
			err = tostring(raw_output)
			vim.notify("ninjection.get_inj_lang: Error calling vim.treesitter.get_node_text()",
				vim.log.levels.WARN)
			return nil, err
		end
		candidate_text = raw_output
		if not candidate_text then
			err = "ninjection.get_inj_lang: Could not retrieve injected " ..
				"language text calling vim.treesitter.get_node_text()"
			vim.notify(err, vim.log.levels.WARN)
			return nil, err
		end
		-- Gross regex magic
		candidate_text = candidate_text:gsub("^%s*(.-)%s*$", "%1")
		---@type string
		local lang = candidate_text:gsub("^#%s*", "")

		-- Check language against table of languages mapped to LSPs
		if lang and cfg.lsp_map[lang] then
			return lang, nil
		end

		err = "ninjection.treesitter.get_inj.lang(): no supported injected " ..
			"languages were found."
		vim.notify(err, vim.log.levels.WARN)
		return nil, err
	end

	err = "ninjection.treesitter.get_inj.lang(): no supported injected " ..
		"languages were found."
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

  return s_row, visual_s_col, e_row, visual_e_col
end

return M
