---@module "ninjection.parse"
---@brief
--- The parse module contains all treesitter related functions for ninjection.
---
local M = {}
---@type Ninjection.Config
local cfg = require("ninjection.config").values
local ts = require("vim.treesitter")

---@nodoc
---@return integer[]? cursor_pos, string? err
--- Cursor position (1:0) - indexed
local function get_cursor()
	---@type boolean, unknown?
	local cur_ok, cur_pos = pcall(vim.api.nvim_win_get_cursor, 0)
	if not cur_ok or type(cur_pos) ~= "table" then
		---@type string
		local err = "ninjection.parse.get_cursor() error: Failed to get cursor position."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end
	---@cast cur_pos integer[]

	return cur_pos
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
	---@type boolean, vim.treesitter.Query?
	local qry_ok, parsed_query
	if cfg.inj_lang_queries and cfg.inj_lang_queries[lang] then
		qry_ok, parsed_query = pcall(ts.query.parse, lang, cfg.inj_lang_queries[lang])
	else
		qry_ok, parsed_query = pcall(ts.query.get, lang, "injections")
	end

	if not qry_ok or not parsed_query then
		local err = "ninjection.parse.get_query() error: Failed to parse Treesitter query for "
			.. lang
			.. " ensure a query string is defined in your config or nvim-treesitter provides an injection scm for "
			.. lang
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end
	---@cast parsed_query vim.treesitter.Query

	return parsed_query, nil
end

---@nodoc
---@param bufnr integer -- Buffer number to get the root node from.
---@param lang string -- Treesitter language to parse for.
---
---@return TSNode? root -- The root node of the syntax tree, or nil on failure.
---@return string? err -- Error message if any failure occurred, or nil.
local function get_root(bufnr, lang)
	---@type vim.treesitter.LanguageTree?, string?
	local ts_langtree, lt_err = vim.treesitter.get_parser(bufnr, lang, { error = false })
	if not ts_langtree then
		---@type string
		local err = "ninjection.parse.get_root() error: Failed to get language tree for bufnr "
			.. bufnr
			.. " and lang "
			.. lang
			.. " ... "
			.. tostring(lt_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end
	---@cast ts_langtree vim.treesitter.LanguageTree

	---@type TSTree[]?
	local p_trees = ts_langtree:parse()
	if not p_trees or #p_trees == 0 then
		---@type string
		local err = "ninjection.parse.get_root() error: No language trees parsed."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end

	---@type TSTree
	local tree = p_trees[1]
	if not tree then
		---@type string
		local err = "ninjection.parse.get_root() error: The first parsed tree is nil."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end
	---@cast tree TSTree

	---@type TSNode?
	local root = tree:root()
	if not root then
		---@type string
		local err = "ninjection.parse.get_root() error: The root node is nil."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end
	---@cast root TSNode

	return root, nil
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

	-- Check for the inj_lang and inj_text labels in the query captures. This is
	-- defined from cfg.inj_lang_queries.[ft] where ft is the name of the table
	-- string indicating the file type.
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
		---@type string
		local err = "ninjection.parse.get_capture_pair() warning: no capture pairs found."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return nil, err
	end

	-- Iterate through all matched queries and return the first valid pair of
	-- injected language string and node
	for _, match, _ in query:iter_matches(root, bufnr, 0, -1) do
		---@type table?, table?
		local inj_lang_matches = match[inj_lang_index]
		local inj_text_matches = match[inj_text_index]
		if type(inj_lang_matches) == "table" and type(inj_text_matches) == "table" then
			---@cast inj_lang_matches table
			---@cast inj_text_matches table

			for i = 1, math.min(#inj_lang_matches, #inj_text_matches) do
				---@type TSNode?, TSNode?
				local inj_lang_node = inj_lang_matches[i]
				local inj_text_node = inj_text_matches[i]

				if inj_lang_node ~= nil and inj_text_node ~= nil then
					---@cast inj_lang_node TSNode
					---@cast inj_text_node TSNode

					if not inj_text_node.range and cfg.debug then
						vim.notify(
							"ninjection.parse.get_capture_pair() warning:  inj_text_node is not a valid TSNode (missing `range()` method)\n"
								.. vim.inspect(inj_text_node),
							vim.log.levels.WARN
						)
					elseif ts.node_contains(inj_text_node, cur_point) then
						---@type string?
						local capture_text = get_node_text(inj_lang_node, bufnr)
						if capture_text and type(capture_text) == "string" then
							---@cast capture_text string
							---@type string
							local inj_lang_text = capture_text:gsub(lang_pattern, "%1")

							-- Success condition: Returns the text identifying the language
							-- being injected and the TSNode paired with that lable.
							return { inj_lang = inj_lang_text, node = inj_text_node }
						else
							if not inj_text_node.range and cfg.debug then
								vim.notify(
									("injection.parse.get_capture_pair() warning: inj_text_node %s is missing range()"):format(
										inj_text_node:type()
									),
									vim.log.levels.WARN
								)
							end

							-- Warning condition: valid nodes and capture labels were identified
							-- but no text was found indicating what language is being injected.
							---@type string
							local err = "ninjection.parse.get_capture_pair() warning: Nothing returned."
							if cfg.debug then
								vim.notify(err, vim.log.levels.WARN)
							end

							return nil, err
						end
					end
				end
			end
		end
	end

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
	-- Failed condition: No matches found for injected language pairs, only indicates
	-- an error if the cursor position is in a valid location and a correct inj_lang
	-- queries are configured.
	return nil, nil
end

---@nodoc
---@param bufnr integer Buffer number to check filetype for
---@return string? ft, string? err Detected filetype or error
local function get_ft(bufnr)
	---@type boolean, unknown?
	local val_ok, ft = pcall(function()
		return vim.api.nvim_get_option_value("filetype", { buf = bufnr })
	end)

	if not val_ok or type(ft) ~= "string" then
		---@type string
		local err = "ninjection.parse.get_ft() error: Failed to get filetype for bufnr: " .. bufnr
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end
	---@cast ft string
	return ft, nil
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
---  - ft: `string` - The filetype of the buffer containing the injection
---  - lang: `string` - the injected language (not the parent filetype)
---  - node: `TSNode` - the Treesitter node element (see :h TSNode)
---  - range: `NJRange` - row/col ranges for the node
---  - text: `string` - the injected language text (modified by any applicable
---  filetype functions)
---
M.get_injection = function(bufnr)
	---@type string?, string?
	local ft, ft_err
	ft, ft_err = get_ft(bufnr)
	if not ft then
		---@type string
		local err = "ninjection.parse.get_injection() error: failed to retrieve filetype ... " .. tostring(ft_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end
	---@cast ft string

	---@type integer[]?, string?
	local cursor_pos, cur_err
	cursor_pos, cur_err = get_cursor()
	if not cursor_pos then
		---@type string
		local err = "ninjection.parse.get_injection() error: failed to get cursor position ... " .. tostring(cur_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end
	---@cast cursor_pos integer[]

	---@type vim.treesitter.Query?, string?
	local parsed_query, qry_err = get_query(ft)
	if not parsed_query then
		---@type string
		local err = "ninjection.parse.get_injection() warning: failed to get parsed query ... " .. tostring(qry_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return nil, err
	end
	---@cast parsed_query vim.treesitter.Query

	---@type TSNode?, string?
	local root, root_err = get_root(bufnr, ft)
	if not root then
		---@type string
		local err = "ninjection.parse.get_injection() error: failed to get parse root node ... " .. tostring(root_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end
	---@cast root TSNode

	---@type NJCapturePair?, string?
	local capture, cap_err = get_capture_pair(bufnr, cursor_pos, ft, root, parsed_query)
	if not capture then
		---@type string
		local err = "ninjection.parse.get_injection() warning, no injected language found: " .. tostring(cap_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return nil, err
	end
	---@cast capture NJCapturePair

	---@type string?
	local injection_text = get_node_text(capture.node, bufnr)
	if not injection_text then
		---@type string
		local err = "ninjection.parse.get_injection() warning, no injected text found."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return nil, err
	end
	---@cast injection_text string

	---@type integer
	local s_row, s_col, e_row, e_col = capture.node:range()

	---@type NJNodeTable
	local injection = {
		ft = ft,
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
