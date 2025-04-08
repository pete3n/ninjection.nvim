---@module "ninjection.parse"
---@brief
--- The parse module contains all treesitter related functions for ninjection.
---
local M = {}
---@type Ninjection.Config
local cfg = require("ninjection.config").values
local ts = require("vim.treesitter")

---@nodoc
---@param bufnr integer Buffer handle to check filetype support.
---@return string? ft Filetype language, if supported
local function check_lang(bufnr)
	---@type boolean, unknown?
	local ok, raw_output = pcall(function()
		return vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	end)
	if not ok then
		error("ninjeciton.parse.get_node_table() error: " .. tostring(raw_output), 2)
	end
	if type(raw_output) ~= "string" then
		if cfg.debug then
			vim.notify("ninjection.parse.get_node_table() warning: no filetype detected", vim.log.levels.WARN)
		end
	end
	local ft = raw_output
	---@cast ft string

	local query = cfg.inj_lang_queries[ft]
	if not query or type(query) ~= "string" or query == "" then
		-- Fallback to built in queries
		-- TODO: Implement fallback option from vim.treesitter.get_query(lang, "injections")
		if cfg.debug then
			vim.notify(
				"ninjeciton.parse.get_node_table() warning: injected language "
					.. "query available for filetype: "
					.. ft,
				vim.log.levels.WARN
			)
		end
		return nil
	end
	return ft
end

---@tag ninjection.parse.qet_query()
---@brief
--- Retrieves a parsed query from Treesitter given a language and pattern.
---
--- Parameters ~
---@param lang? string? - Default: `"nix"` - language grammar to parse with.
---
---@return vim.treesitter.Query? parsed_query
---The parsed Treesitter Query object
---
M.get_query = function(lang)
	lang = lang or "nix"
	---@cast lang string
	---@type boolean, unknown, vim.treesitter.Query?
	local ok, raw_output, parsed_query

	ok, raw_output = pcall(function()
		return ts.query.parse(lang, cfg.inj_lang_queries[lang])
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	if not raw_output.query then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_query() warning: No Query result "
					.. "returned from calling vim.treesitter.query.parse()",
				vim.log.levels.WARN
			)
		end
		return nil
	end
	parsed_query = raw_output
	---@cast parsed_query vim.treesitter.Query

	return parsed_query
end

---@tag ninjection.parse.get_root()
---@brief
--- Parses the root tree for a language in a buffer.
---
--- Parameters ~
---@param bufnr integer - Handle for buffer to parse.
---@param lang? string  - Default: `"nix"` - language to parse with.
---
---@return TSNode? root
--- Root node of the TSTree for the language.
---
M.get_root = function(bufnr, lang)
	lang = lang or "nix"
	---@type boolean, unknown, vim.treesitter.LanguageTree?
	local ok, raw_output, parser
	ok, raw_output = pcall(function()
		return vim.treesitter.get_parser(bufnr, lang)
	end)
	if not ok then
		error("ninjection.parse.get_root() error: " .. tostring(raw_output), 2)
	end
	if not raw_output then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_root() warning: No parser available " .. "for: " .. lang,
				vim.log.levels.WARN
			)
		end
		return nil
	end
	parser = raw_output
	---@cast parser vim.treesitter.LanguageTree

	---@type TSTree?
	local tree = parser:parse()[1]
	if not tree then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get.root() warning: No syntax tree found " .. "for " .. lang,
				vim.log.levels.WARN
			)
		end
		return nil
	end
	---@cast tree TSTree

	---@type TSNode?
	local root = tree:root()
	if not root then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get.root() warning: No syntax tree root " .. "found for " .. lang,
				vim.log.levels.WARN
			)
		end
	end
	---@cast root TSNode

	return root
end

---@tag ninjection.parse.get_node_table()
---@brief
--- Identifies the injected language node at the current cursor position
--- with start and ending coordinates.
---
--- Parameters ~
---@param bufnr integer - The buffer handle to query in.
---
---@return NJNodeTable? table, string? err
--- Returns a table containing:
---  - node: `TSNode` - the Treesitter node element (see :h TSNode).
---  - range: `NJRange` - row/col ranges for the node.
---  NOTE: Coordinates may not match the actual text locations
---  (see: `ninjection.parse.get_visual_range()` for this).
--
M.get_node_table = function(bufnr)
	---@type boolean, unknown, string?, integer[]?
	local ok, raw_output, err, cursor

	local ft = check_lang(bufnr)
	if not ft then
		return nil
	end
	---@cast ft string

	ok, raw_output = pcall(function()
		return vim.api.nvim_win_get_cursor(0) -- current window cursor position
	end)
	if not ok then
		error("ninjection.parse.get_node_table() error: " .. tostring(raw_output), 2)
	end
	if type(raw_output) ~= "table" then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_node_table() warning: Could not "
					.. "determine cursor location in current window from "
					.. "vim.api.nvim_win_get_cursor(0)",
				vim.log.levels.WARN
			)
		end
		return nil
	end
	cursor = raw_output
	---@cast cursor integer[]

	---@type integer
	local cur_row = cursor[1] - 1 --convert to 0-indexed
	---@type integer
	local cur_col = cursor[2]

	--- @type vim.treesitter.Query?
	local parsed_query
	parsed_query, err = M.get_query(ft)
	if not parsed_query then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_node_info() warning: get_query() " .. " returned nil: " .. tostring(err),
				vim.log.levels.WARN
			)
		end
		return nil, err
	end
	---@cast parsed_query vim.treesitter.Query

	---@type TSNode|nil
	local root
	root, err = M.get_root(bufnr)
	if not root then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_node_table() warning: No root " .. "returned: " .. tostring(err),
				vim.log.levels.WARN
			)
		end
		return nil, err
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
			inj_range = { s_row = s_row, s_col = s_col, e_row = e_row, e_col = e_col }
			-- Trim leading and training lines to remove ''
			inj_range.s_row = inj_range.s_row + 1
			inj_range.e_row = inj_range.e_row - 1

			local cur_point = { cur_row, cur_col, cur_row, cur_col }
			ok, raw_output = pcall(function()
				return ts.node_contains(node, cur_point)
			end)
			if not ok then
				error("ninjection.parse.get_node_table() error: " .. tostring(raw_output), 2)
			end
			if raw_output == true then
				---@type NJNodeTable
				local ret_table = { node = node, range = inj_range }
				return ret_table
			end
		end
	end

	if cfg.debug then
		vim.notify(
			"ninjection.parse.get_node_table(): No injection.content " .. "id found in node.",
			vim.log.levels.WARN
		)
	end

	return nil
end

---@tag ninjection.parse.get_inj_lang()
---@brief
--- Parse an injected content node for an associated language comment.
---
--- Parameters ~
---@param bufnr integer - Handle for the buffer to query in.
--- injections in.
---
---@return string? inj_lang , string? err - Injected language identified.
---
M.get_inj_lang = function(bufnr)
	---@type boolean, unknown, string?, vim.treesitter.Query?, string?
	local ok, raw_output, err, parsed_query, ft

	ft = check_lang(bufnr)
	if not ft then
		return nil
	end
	---@cast ft string

	parsed_query, err = M.get_query(ft)
	if not parsed_query then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_inj_lang() warning: Could not parse "
					.. "the Treesitter query with get_query(): "
					.. tostring(err),
				vim.log.levels.WARN
			)
		end
		return nil
	end
	---@cast parsed_query vim.treesitter.Query

	---@type TSNode|nil
	local root
	root, err = M.get_root(bufnr, ft)
	if not root then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_inj_lang() warning: Could not "
					.. "determine the syntax tree root from get_root(): "
					.. tostring(err),
				vim.log.levels.WARN
			)
		end
		return nil
	end
	---@cast root TSNode

	---@type NJNodeTable|nil
	local node_info
	node_info, err = M.get_node_table(bufnr)
	if not node_info then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_inj_lang() warning: Could not "
					.. "determine injected content calling get_node_table(): "
					.. tostring(err),
				vim.log.levels.WARN
			)
		end
		return nil
	end
	---@cast node_info NJNodeTable

	---@type integer|nil
	local node_s_row = node_info.range.s_row
	if not node_s_row then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_inj_lang() warning: Could not "
					.. "determine injected language starting row calling get_node_table(): ",
				vim.log.levels.WARN
			)
		end
		return nil
	end
	---@cast node_s_row integer

	---@type {node: TSNode, e_row: integer}|nil
	local candidate_info
	for id, node, _, _ in parsed_query:iter_captures(root, bufnr, 0, -1) do
		---@cast id integer
		---@cast node TSNode
		---@type string
		local capture_name = parsed_query.captures[id]
		if capture_name == "injection.language" then
			---@type integer[]
			local capture_range = { node:range() }
			---@type integer
			local e_row = capture_range[3]
			-- Assuming the language comment is entirely above the injection block,
			-- we will find the matching node that has the greatest end row.
			if e_row < node_s_row then
				if not candidate_info or (e_row > candidate_info.e_row) then
					candidate_info = { node = node, e_row = e_row }
				end
			end
		end
	end
	---@cast candidate_info {node: TSNode, e_row: integer}

	if candidate_info then
		---@type string|nil
		local candidate_text
		ok, raw_output = pcall(function()
			return vim.treesitter.get_node_text(candidate_info.node, bufnr)
		end)
		if not ok then
			error(tostring(raw_output), 2)
		end
		candidate_text = raw_output
		if not candidate_text then
			if cfg.debug then
				vim.notify(
					"ninjection.get_inj_lang warning: Could not retrieve "
						.. "injected language text calling vim.treesitter.get_node_text()"
						.. tostring(raw_output),
					vim.log.levels.WARN
				)
			end
			return nil
		end
		---@cast candidate_text string

		-- Gross regex magic
		candidate_text = candidate_text:gsub("^%s*(.-)%s*$", "%1")

		---@type string|nil
		local inj_lang = candidate_text:gsub("^#%s*", "")
		if not inj_lang then
			if cfg.debug then
				vim.notify(
					"ninjection.parse.get_inj.lang() warning: No language " .. "comment could be parsed.",
					vim.log.levels.WARN
				)
			end
			return nil
		end
		---@cast inj_lang string

		-- Check language against table of languages mapped to LSPs
		if inj_lang and cfg.lsp_map[inj_lang] then
			return inj_lang
		end

		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_inj.lang() warning: No supported "
					.. "injected languages were found. Check your configuration.",
				vim.log.levels.WARN
			)
		end
		return nil
	end

	if cfg.debug then
		vim.notify(
			"ninjection.parse.get_inj.lang() warning: No injected languages " .. "were found.",
			vim.log.levels.WARN
		)
	end

	return nil
end

-- Treesitter's selection for "injected.content" doesn't match the actual text
-- selected. We need a function that adjusts the selection to match.

---@tag ninjection.parse.get_visual_range()
---@brief
--- Gets an adjusted "visual" range for a node by approximating the
--- range of text that is actually seen (as returned by get_node_text).
--- This makes an opinionated assumption about formatting that expects:
---
---	`assigment = # injected_lang_comment
---	`''
---	`	 injected.content
---	`'';
---
---	The '' and ''; characters are not important, but the dedicated lines for
--- comment delimiters and the language comment above that block are important.
---
--- Parameters ~
---@param node TSNode - The Treesitter node to select in.
---@param bufnr integer - Handle for the buffer to work in.
---
---@return NJRange? vs_range, string? err - Range of text selected.
---
M.get_visual_range = function(node, bufnr)
	---@type boolean, unknown, string?, integer[]?
	local ok, raw_output, err, range

	range = { node:range() }
	if not range or #range < 4 then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_visual_range() warning: No valid " .. " selection range found in range()",
				vim.log.levels.WARN
			)
		end
		return nil
	end
	---@cast range integer[]

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_lines(bufnr, range[1], range[3], false)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	---@type string[]|nil
	local raw_lines = raw_output
	if not raw_lines or #raw_lines == 0 then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_visual_range() warning: Nothing "
					.. "returned from calling vim.api.nvim_buf_get_lines()",
				vim.log.levels.WARN
			)
		end
		return nil
	end
	---@cast raw_lines string[]

	ok, raw_output = pcall(function()
		return ts.get_node_text(node, bufnr)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	---@type string|nil
	local visual_text = raw_output
	if not visual_text then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_visual_range() warning: No text "
					.. "returned from vim.treesitter.get_node_text()",
				vim.log.levels.WARN
			)
		end
		return nil
	end
	---@cast visual_text string

	ok, raw_output = pcall(function()
		return vim.split(visual_text, "\n", { plain = true })
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify(
			"ninjection.parse.get_visual_range(): Error calling " .. "vim.split(): " .. err,
			vim.log.levels.ERROR
		)
		return nil, err
	end
	---@type string[]|nil
	local visual_lines = raw_output
	if not visual_lines or #visual_lines == 0 then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_visual_range(): No strings returned" .. "from vim.split()",
				vim.log.levels.WARN
			)
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
	local vs_range = { s_row = range[1], s_col = visual_s_col, e_row = range[3], e_col = visual_e_col }

	return vs_range
end

return M
