---@module "ninjection.parse"
---@brief
--- The parse module contains all treesitter related functions for ninjection.
---
local M = {}
---@type Ninjection.Config
local cfg = require("ninjection.config").values
local ts = require("vim.treesitter")

---@nodoc
---@return integer[]? cursor_pos, string? err cursor position (1:0) - indexed
local function get_cursor()
	---@type boolean, unknown?
	local ok, result = pcall(vim.api.nvim_win_get_cursor, 0)

	if not ok then
		return nil, tostring(result)
	end

	if type(result) ~= "table" then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_node_info() warning: Could not " .. "determine cursor location",
				vim.log.levels.WARN
			)
		end
		return nil, nil
	end

	---@cast result integer[]
	return result
end

---@nodoc
---@param lang? string? Default: `"nix"` - language grammar to parse with
---
---@return vim.treesitter.Query? parsed_query, string? err Parsed query or err
---
local function get_query(lang)
	lang = lang or "nix"
	---@cast lang string

	-- Try using cfg.inj_lang_queries[lang] if it exists,
	-- otherwise fall back to the default built-in Treesitter query
	---@type boolean, unknown?
	local ok, result
	if cfg.inj_lang_queries and cfg.inj_lang_queries[lang] then
		---@type boolean, unknown?
		ok, result = pcall(ts.query.parse, lang, cfg.inj_lang_queries[lang])
	else
		ok, result = pcall(ts.query.get, lang, "injections")
	end

	if not ok then
		return nil, tostring(result)
	end
	if not result or not result.query then
		if cfg.debug then
			vim.notify("ninjection.parse.get_query() warning: No Query result ", vim.log.levels.WARN)
		end
		return nil, nil
	end

	---@cast result vim.treesitter.Query
	return result, nil
end

---@nodoc
---@param bufnr integer Buffer number
---@param lang string Treesitter language
---
---@return TSNode? root, string? err
local function get_root(bufnr, lang)
	---@type boolean, unknown?
	local ok, result = pcall(function()
		local parser = vim.treesitter.get_parser(bufnr, lang)
		local tree = parser:parse()[1]
		return tree:root()
	end)

	if not ok then
		return nil, tostring(result)
	end

	---@cast result TSNode
	return result, nil
end

---@nodoc
---@param node TSNode Treesitter node
---@param bufnr integer Buffer number
---@return string? text
local function get_node_text(node, bufnr)
	---@type boolean, unknown?
	local ok, result = pcall(ts.get_node_text, node, bufnr)
	if ok then
		---@cast result string
		return result
	end
	if cfg.debug then
		vim.notify("Error retrieving node text: " .. tostring(result), vim.log.levels.ERROR)
	end
	return nil
end

---@nodoc
---@param bufnr integer Buffer number
---@param cursor_pos integer[] (1:0) row:col indexed
---@param ft string Filetype
---@param root TSNode Root node of syntax tree
---@param query vim.treesitter.Query Parsed Treesitter query object
---
---@return NJCapturePair? lang_pair, string? err
--- Returns an injected language node and its associated language string
--- provided the cursor is within the bounds of the node.
local function get_capture_pair(bufnr, cursor_pos, ft, root, query)
	-- Convert (1:0) index to (0:0) index for node range comparison
	---@type table<integer, integer, integer, integer>
	local cur_point = { cursor_pos[1] - 1, cursor_pos[2], cursor_pos[1] - 1, cursor_pos[2] }

	---@type string
	local lang_pattern = cfg.inj_lang_comment_pattern and cfg.inj_lang_comment_pattern[ft] or "#%s*([%w%p]+)%s*"

	---@type integer?, integer?
	local inj_lang_index, inj_text_index
	for i, name in ipairs(query.captures) do
		if name == "inj_lang" then
			inj_lang_index = i
		elseif name == "inj_text" then
			inj_text_index = i
		end
	end

	if not inj_lang_index or not inj_text_index then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_capture_pair() warning: no capture pairs " .. "found for inj_lang and inj_text.",
				vim.log.levels.WARN
			)
		end
		return nil, nil
	end

	for _, match, _ in query:iter_matches(root, bufnr, 0, -1) do
		local inj_lang_node = match[inj_lang_index]
		local inj_text_node = match[inj_text_index]

		if inj_lang_node ~= nil and inj_text_node ~= nil then
			---@cast inj_lang_node TSNode
			---@cast inj_text_node TSNode
			if type(inj_text_node) ~= "userdata" or not inj_text_node.range then
				if cfg.debug then
					vim.notify(
						"ninjection: inj_text_node is not a valid TSNode (missing `range()` method)",
						vim.print(vim.inspect(inj_text_node)),
						vim.log.levels.ERROR
					)
				end
			end
		else
			if ts.node_contains(inj_text_node, cur_point) then
				local capture_text = get_node_text(inj_lang_node, bufnr)
				if capture_text then
					local inj_lang_text = capture_text:gsub(lang_pattern, "%1")
					return { inj_lang = inj_lang_text, node = inj_text_node }
				end
			end
		end
	end

	-- If no valid match found, log a warning
	if cfg.debug then
		vim.notify(
			string.format(
				"ninjection.parse.get_capture_pair(): no matching TSNode found at cursor (%d, %d)",
				cur_point[1] + 1,
				cur_point[2]
			),
			vim.log.levels.WARN
		)
	end
	return nil, nil
end

---@nodoc
---@param bufnr integer Buffer number to check filetype for
---@return string? ft, string? err Detected filetype or error
M.get_ft = function(bufnr)
	---@type boolean, unknown?
	local ok, result = pcall(function()
		return vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	end)

	if not ok then
		return nil, tostring(result)
	end

	if type(result) ~= "string" then
		---@type string
		if cfg.debug then
			vim.notify("ninjection.parse.get_ft() warning: no filetype detected", vim.log.levels.WARN)
		end
		return nil, nil
	end

	---@cast result string
	return result, nil
end

---@tag ninjection.parse.get_node_info()
---@brief
--- Identifies the injected language node at the current cursor position
--- with start and ending coordinates.
---
--- Parameters ~
---@param bufnr integer - The buffer handle to query in.
---
---@return NJNodeTable? injection, string? err
--- Returns a table containing:
---  - lang: `string` - the injected language (not the parent filetype)
---  - node: `TSNode` - the Treesitter node element (see :h TSNode)
---  - range: `NJRange` - row/col ranges for the node
---  - text: `string` - the injected language text (modified by any applicable
---  filetype functions)
---
M.get_injection = function(bufnr)
	---@type string?, string?
	local ft, err
	ft, err = M.get_ft(bufnr)
	if not ft then
		error("Error, failed to get filetype: " .. err, 2)
	end
	---@cast ft string

	---@type integer[]?
	local cursor_pos
	cursor_pos, err = get_cursor()
	if not cursor_pos then
		error("Error, failed to get cursor position: " .. err, 2)
	end
	---@cast cursor_pos integer[]

	---@type vim.treesitter.Query?
	local query
	query, err = get_query(ft)
	if not query then
		error("Error, failed to parse treesitter query: " .. err, 2)
	end
	---@cast query vim.treesitter.Query

	---@type TSNode?
	local root
	root, err = get_root(bufnr, ft)
	if not root then
		error("Error, failed to parse root node: " .. err, 2)
	end

	---@type NJCapturePair?
	local capture
	capture, err = get_capture_pair(bufnr, cursor_pos, ft, root, query)
	if not capture then
		if cfg.debug then
			vim.notify(
				"ninjection.parse.get_injection() warning, no injected language found: " .. tostring(err),
				vim.log.levels.WARN
			)
		end
		return nil, nil
	end
	---@cast capture NJCapturePair

	---@type string?
	local injection_text = get_node_text(capture.node, bufnr)
	if not injection_text then
		if cfg.debug then
			vim.notify("ninjection.parse.get_injection() warning, no injected text found: ", vim.log.levels.WARN)
		end
		return nil, nil
	end
	---@cast injection_text string

	---@type integer
	local s_row, s_col, e_row, e_col = capture.node:range()

	---@type NJNodeTable
	local injection = {
		pair = capture,
		range = {
			s_row = s_row,
			s_col = s_col,
			e_col = e_col,
			e_row = e_row,
		},
		text = injection_text,
		cursor_pos = cursor_pos,
	}

	return injection, nil
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
