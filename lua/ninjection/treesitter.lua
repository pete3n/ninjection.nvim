--- Treesitter helper functions for ninjection
---@class ninjection.treesitter
local M = {}
local cfg = {}
require("ninjection.types")

local ts = require("vim.treesitter")

M.set_config = function(config)
	cfg = config
end


--- Function: Get a parsed query from Treesitter given a language and pattern.
---@param query string Lua-literal string for Treesitter query.
---@param lang? string Default: "nix", language grammar to parse with.
---@return vim.treesitter.Query|nil parsed_query The parsed Treesitter Query object
---@return nil|string err Error string, if applicable
M.get_query = function(query, lang)
	---@type string|nil
	lang = lang or "nix"
	---@type boolean, any|nil, vim.treesitter.Query|nil
	local ok, raw_output, parsed_query

	ok, raw_output = pcall(function()
		return ts.query.parse(lang, query)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	parsed_query = raw_output
	if not parsed_query then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get_query() warning: No Query result " ..
			"returned from calling vim.treesitter.query.parse()", vim.log.levels.WARN)
		end
		return nil
	end
	---@cast parsed_query vim.treesitter.Query

	return parsed_query
end


--- Function: Parses the root tree for a language in a buffer.
---
---@param bufnr integer Handle for buffer to parse.
---@param lang? string Default: "nix" language to parse with.
---@return TSNode|nil root root node of the TSTree for the language.
---@return nil|string err Error string, if applicable.
M.get_root = function (bufnr, lang)
	lang = lang or "nix"
	---@type boolean, any|nil, string|nil, vim.treesitter.LanguageTree|nil
	local ok, raw_output, parser
  ok, raw_output = pcall(function()
		return vim.treesitter.get_parser(bufnr, "nix")
	end)
	if not ok then
		error("ninjection.treesitter.get_root() error: " .. tostring(raw_output),2)
	end
	parser = raw_output
  if not parser then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get_root() warning: No parser available " ..
				"for: " .. lang, vim.log.levels.WARN)
		end
    return nil
  end
	---@cast parser vim.treesitter.LanguageTree

	---@type TSTree|nil
  local tree = parser:parse()[1]
  if not tree then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get.root() warning: No syntax tree found " ..
			"for " .. lang, vim.log.levels.WARN)
		end
		return nil
  end
	---@cast tree TSTree

	---@type TSNode|nil
	local root = tree:root()
	if not root then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get.root() warning: No syntax tree root " ..
			"found for " .. lang, vim.log.levels.WARN)
		end
	end
	---@cast root TSNode

  return root
end


--- Function: Identify the injected language node at the current cursor position
--- with start and ending coordinates.
---
---@param query string Pattern to identify an injected lang.
---@param lang? string Default: "nix" language grammar to use for parsing.
---@return NJNodeTable|nil table
--- Return: On success, a table containing:
--- node: TSNode - the Treesitter node element (see :h TSNode).
--- range: NJRange - s_col, s_row, e_col, e_row, integer coordinates for node.
--- NOTE: Coordinates may not match the actual text locations (see:
--- get_visual_range() for this).
---@return nil|string err Error string, if applicable
M.get_node_table = function(query, lang)
	lang = lang or "nix"
	---@type boolean, any|nil, string|nil, integer|nil, integer[]|nil
	local ok, raw_output, err, bufnr, cursor

	ok, raw_output = pcall(function()
		return vim.api.nvim_get_current_buf()
	end)
	if not ok then
		error("ninjection.treesitter.get_node_table() error: " ..
			tostring(raw_output),2)
	end
	bufnr = raw_output
	if not bufnr then
		error("ninjection.treesitter.get_node_table() error: No buffer handle " ..
			"returned: " .. tostring(raw_output),2)
	end
	---@cast bufnr integer

	ok, raw_output = pcall(function()
		return	vim.api.nvim_win_get_cursor(0) -- current window cursor position
	end)
	if not ok then
		error("ninjection.treesitter.get_node_table() error: " .. tostring(raw_output),2)
	end
	cursor = raw_output
	if not cursor then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get_node_table() warning: Could not " ..
				"determine cursor location in current window from " ..
				"vim.api.nvim_win_get_cursor(0)", vim.log.levels.WARN)
		end
		return nil
	end
	---@cast cursor integer[]

	---@type integer
	local cur_row = cursor[1] - 1 --convert to 0-indexed
	---@type integer
	local cur_col = cursor[2]

	--- @type vim.treesitter.Query|nil
	local parsed_query
	parsed_query, err = M.get_query(query, lang)
	if not parsed_query then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get_node_info() warning: get_query() " ..
				" returned nil: " .. tostring(err), vim.log.levels.WARN)
		end
		return nil
	end
	---@cast parsed_query vim.treesitter.Query

	---@type TSNode|nil
	local root
	root, err = M.get_root(bufnr)
	if not root then
		if cfg.suppress_warnings == false then
				vim.notify("ninjection.treesitter.get_node_table() warning: No root " ..
					"returned: " .. tostring(err), vim.log.levels.WARN)
		end
		return nil
	end
	---@cast root TSNode

	for id, node, _, _ in parsed_query:iter_captures(root, bufnr, 0, -1) do
		---@cast id integer
		---@cast node TSNode
		---@type string
		local capture_name = parsed_query.captures[id]

		if capture_name == "injection.content" then
			---@type integer, integer, integer, integer
			local s_row, s_col, e_row, e_col = node:range()
			---@type NJRange
			local inj_range
			if cfg.injected_comment_newline then
				inj_range = { s_row = s_row, s_col = s_col, e_row = e_row, e_col = e_col }
			else
				inj_range = { s_row = s_row, s_col = s_col, e_row = e_row,
					e_col = e_col }
			end
			---@cast inj_range integer[]

			local cur_point = { cur_row, cur_col, cur_row, cur_col }
			ok, raw_output = pcall(function()
				return ts.node_contains(node, cur_point)
			end)
			if not ok then
				error("ninjection.treesitter.get_node_table() error: " ..
					tostring(raw_output),2)
			end
			if raw_output == true then
				---@type NJNodeTable
				local ret_table = { node = node, range = inj_range }
				return ret_table
			end
		end
	end

	if cfg.suppress_warnings == false then
		vim.notify("ninjection.treesitter.get_node_table(): No injection.content " ..
		"id found in node.", vim.log.levels.WARN)
	end

	return nil
end

--- Function: Parse an injected content node for an associated language comment.
---
---@param query string Query to identify an injected content node.
---@param bufnr integer Handle for the buffer to query in.
---@param file_lang? string Default: "nix". Parent file language to find injections in.
---@return string|nil inj_lang Injected language identified.
---@return nil|string err  Error string, if applicable.
M.get_inj_lang = function(query, bufnr, file_lang)
	---@type boolean, any|nil, string|nil, vim.treesitter.Query|nil
	local ok, raw_output, err, parsed_query
	file_lang = file_lang or "nix"

	parsed_query, err = M.get_query(query, file_lang)
	if not parsed_query then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get_inj_lang() warning: Could not parse " ..
			"the Treesitter query with get_query(): " .. tostring(err), vim.log.levels.WARN)
		end
		return nil
	end
	---@cast parsed_query vim.treesitter.Query

	---@type TSNode|nil
	local root
	root, err = M.get_root(bufnr, file_lang)
	if not root then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get_inj_lang() warning: Could not " ..
				"determine the syntax tree root from get_root(): " .. tostring(err),
				vim.log.levels.WARN)
		end
		return nil
	end
	---@cast root TSNode

	---@type NJNodeTable|nil
	local node_info
  node_info, err = M.get_node_table(cfg.inj_lang_query, file_lang)
  if not node_info then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get_inj_lang() warning: Could not " ..
				"determine injected content calling get_node_table(): " .. tostring(err),
				vim.log.levels.WARN)
		end
		return nil
  end
	---@cast node_info NJNodeTable

	---@type integer|nil
	local node_s_row = node_info.range.s_row
	if not node_s_row then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get_inj_lang() warning: Could not " ..
				"determine injected language starting row calling get_node_table(): ", 
				vim.log.levels.WARN)
		end
		return nil
	end
	---@cast node_s_row integer

	---@type table|nil
	local candidate_info
  for id, node, _ in parsed_query:iter_captures(root, bufnr, 0, -1) do
		---@cast id integer
		---@cast node TSNode
    local capture_name = parsed_query.captures[id]
    if capture_name == "injection.language" then
			---@type table, integer
			local capture_range, e_row
      capture_range = { node:range() }
			e_row = capture_range[3]
      -- Assuming the language comment is entirely above the injection block,
			-- we will find the matching node that has the greatest end row.
      if e_row < node_s_row then
        if not candidate_info or (e_row > candidate_info.e_row) then
          candidate_info = { node = node, e_row = e_row }
        end
      end
    end
  end
	---@cast candidate_info table

  if candidate_info then
		---@type string|nil
		local candidate_text
		ok, raw_output = pcall(function()
			return vim.treesitter.get_node_text(candidate_info.node, bufnr)
		end)
		if not ok then
			error(tostring(raw_output),2)
		end
		candidate_text = raw_output
		if not candidate_text then
			if cfg.suppress_warnings == false then
				vim.notify("ninjection.get_inj_lang warning: Could not retrieve " ..
					"injected language text calling vim.treesitter.get_node_text()" ..
					tostring(raw_output), vim.log.levels.WARN)
			end
			return nil
		end
		---@cast candidate_text string

		-- Gross regex magic
		candidate_text = candidate_text:gsub("^%s*(.-)%s*$", "%1")

		---@type string|nil
		local inj_lang = candidate_text:gsub("^#%s*", "")
		if not inj_lang then
			if cfg.suppress_warnings == false then
				vim.notify("ninjection.treesitter.get_inj.lang() warning: No language " ..
				"comment could be parsed.", vim.log.levels.WARN)
			end
			return nil
		end
		---@cast inj_lang string

		-- Check language against table of languages mapped to LSPs
		if inj_lang and cfg.lsp_map[inj_lang] then
			return inj_lang
		end

		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get_inj.lang() warning: No supported " ..
			"injected languages were found. Check your configuration.",
			vim.log.levels.WARN)
		end
		return nil
	end

	if cfg.suppress_warnings == false then
		vim.notify("ninjection.treesitter.get_inj.lang() warning: No injected languages " ..
		"were found.", vim.log.levels.WARN)
	end

	return nil
end


-- Treesitter's selection for "injected.content" doesn't match the actual text
-- selected. We need a function that adjusts the selection to match.

--- Function: Gets an adjusted "visual" range for a node by approximating the
--- range of text that is actually seen (as returned by get_node_text).
--- This makes an opinionated assumption about formatting that expects:
---	assigment = # injected_lang_comment
---	''
---		injected.content
---	'';
---	The '' and ''; characters are not important, but the dedicated lines for
--- comment delimiters and the language comment above that block are important.
---
--- @param node TSNode The Treesitter node to select in.
--- @param bufnr integer Handle for the buffer to work in.
--- @return NJRange|nil vs_range Range of text selected.
--- @return nil|string err Error string, if applicable.
M.get_visual_range = function(node, bufnr)
	---@type boolean, any|nil, string|nil, table|nil
	local ok, raw_output, err, range

	range = { node:range() }
	if not range or #range <4 then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get_visual_range() warning: No valid " ..
				" selection range found in range()", vim.log.levels.WARN)
		end
		return nil
	end
	---@cast range table

	ok, raw_output = pcall(function ()
		return vim.api.nvim_buf_get_lines(bufnr, range[1], range[3], false)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	---@type string[]|nil
  local raw_lines = raw_output
	if not raw_lines or #raw_lines == 0 then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get_visual_range() warning: Nothing " ..
			"returned from calling vim.api.nvim_buf_get_lines()", vim.log.levels.WARN)
		end
		return nil
	end
	---@cast raw_lines string[]

	ok, raw_output = pcall(function()
		return ts.get_node_text(node, bufnr)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	---@type string|nil
	local visual_text = raw_output
	if not visual_text then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get_visual_range() warning: No text " ..
				"returned from vim.treesitter.get_node_text()", vim.log.levels.WARN)
		end
		return nil
	end
	---@cast visual_text string

	ok, raw_output = pcall(function()
		return vim.split(visual_text, "\n", { plain = true })
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.treesitter.get_visual_range(): Error calling " ..
		"vim.split(): " .. err, vim.log.levels.ERROR)
		return nil, err
	end
	---@type string[]|nil
  local visual_lines = raw_output
	if not visual_lines or #visual_lines == 0 then
		if cfg.suppress_warnings == false then
			vim.notify("ninjection.treesitter.get_visual_range(): No strings returned" ..
			"from vim.split()", vim.log.levels.WARN)
		end
		return nil
	end
	---@cast visual_lines string[]

  -- For the first line, find the offset of the visual text in the raw line.
	---@type string, string, integer, integer
	local raw_f_line, visual_f_line, offset_f_col, visual_s_col
  raw_f_line = raw_lines[1]
  visual_f_line = visual_lines[1]
  offset_f_col = raw_f_line:find(visual_f_line, 1, true) or 1
  visual_s_col = range[2] + offset_f_col - 1

  -- For the last line, find the offset of the visual text in the raw line.
	---@type string, string, integer, integer
	local raw_l_line, visual_l_line, offset_l_col, visual_e_col
  raw_l_line = raw_lines[#raw_lines]
  visual_l_line = visual_lines[#visual_lines]
  offset_l_col = raw_l_line:find(visual_l_line, 1, true) or 1
  visual_e_col = range[2] + offset_l_col + #visual_l_line - 1

	---@type NJRange
	local vs_range = { s_row = range[1], s_col = visual_s_col, e_row = range[3],
		e_col = visual_e_col }

  return vs_range
end

return M
