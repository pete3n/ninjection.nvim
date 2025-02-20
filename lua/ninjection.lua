local M = {}
require("ninjection.types")
local ts = require("vim.treesitter")

--- @type ninjection.util
local util = require("ninjection.util")

--- @type ninjection.treesitter
local nts = require("ninjection.treesitter")

if vim.fn.exists(":checkhealth") == 2 then
	require("ninjection.health").check()
end

M.cfg = {
	file_lang = "nix", -- Native file type to search for injected languages in.
	-- Must have a matching entry in inj_lang_queries.
	-- Currently only supports nix, but could be extended.
	preserve_indents = true, -- Re-apply indents from the parent buffer.
	-- This option should be used in conjunction with auto_format because
	-- This will re-apply indents that auto_format normally removes.
	-- If you don't remove them, then they will be re-applied which will increase
	-- the original indenation.
	auto_format = true, -- Format the new child buffer with the provided command
	format_cmd = "_G.format_with_conform()", -- Command for auto_format
	-- TODO: Safety checks for auto_format, and require command, default should
	-- be blank.
	injected_comment_lines = 1, -- Offset comment delimiting lines based on style
	-- preferences. For example, offsetting 1 line would function with this format:
	-- # injected_lang
	-- ''
	-- 		injected content
	-- '';
	--
	-- Offsetting 0 lines would function with this format:
	-- # injected_lang
	-- ''injected content
	-- more injected content
	-- end content'';
	register = "z", -- Register to use to copy injected content.
	suppress_warnings = false, -- true|false only show critical errors
	-- If ninjection is not functioning properly, ensure this is false to debug

	-- TODO: Implement other scratch buffer types, currently only std
	buffer_styles = { "std", "popup", "v_split", "h_split", "tab_r", "tab_l" },
	buffer_style = "std",
	-- TODO: Implement auto-inject on buffer close
	inject_on_close = false,

	-- Contains per-language string literals for Treesitter queries to Identify
	-- injected content nodes.
	inj_lang_queries = {
		nix = [[
						(
							(comment) @injection.language
							.
							[
								(indented_string_expression
									(string_fragment) @injection.content)
								(string_expression
									(string_fragment) @injection.content)
							]
							(#gsub! @injection.language "#%s*([%w%p]+)%s*" "%1")
							(#set! injection.combined)
						)
					]],
	},
	inj_lang_query = nil, -- Dyanmically configured from file_lang and inj_lang_queries.

	-- LSPs associated with injected languages. The keys must match the language 
	-- comment used to identify injected languages, and the value must match the
	-- LSP configured in your lspconfig. 
	lsp_map = {
		bash = "bashls",
		c = "clangd",
		cpp = "clangd",
		javascript = "ts_ls",
		json = "jsonls",
		lua = "lua_ls",
		python = "ruff",
		rust = "rust_analyzer",
		sh = "bashls",
		typescript = "ts_ls",
		yaml = "yamlls",
		zig = "zls",
	},
}

-- Set the inj_lang_query based on the current file_lang.
M.cfg.inj_lang_query = M.cfg.inj_lang_queries[M.cfg.file_lang] or M.cfg.inj_lang_query
util.set_config(M.cfg)
nts.set_config(M.cfg)

M.setup = function(args)
	-- Merge user args with default config
	if args and args.lsp_map then
		for k, v in pairs(args.lsp_map) do
			M.cfg.lsp_map[k] = v -- Override defaults
		end
	end
end

--- Function: Identify and select injected content text in visual mode.
---@return nil|string err Error string, if applicable.
M.select = function()
	---@type boolean, any|nil, string|nil, integer|nil, NJNodeTable|nil
	local ok, raw_output, err, bufnr, node_info

	ok, raw_output = pcall(function()
		return vim.api.nvim_get_current_buf()
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	bufnr = raw_output
	if not bufnr then
		if not M.cfg.suppress_warnings then
			vim.notify("ninjection.select() warning: Could not get current buffer " ..
				"calling vim.api.nvim_get_current_buf()", vim.log.levels.WARN)
		end
		return nil
	end

	node_info, err = nts.get_node_table(M.cfg.inj_lang_query, M.cfg.file_lang)
	if not node_info then
		if not M.cfg.suppress_warnings then
			vim.notify("ninjection.select() warning: could not retrieve TSNode: " ..
				tostring(err), vim.log.levels.WARN)
		end
		return nil
	end
	if not node_info.node then
		if not M.cfg.suppress_warnings then
			vim.notify("ninjection.select() warning: No valid TSNode returned.",
				vim.log.levels.WARN)
		end
		return nil
	end

	---@type NJRange|nil
	local v_range
	v_range, err = nts.get_visual_range(node_info.node, bufnr)
	if not v_range then
		if not M.cfg.suppress_warnings then
			vim.notify("ninjection.select() warning: no visual range returned: " ..
				tostring(err), vim.log.levels.WARN)
		end
		return nil
	end

	-- Set marks to select ranges with a custom offset
	ok, raw_output = pcall(function()
		return vim.fn.setpos("'<", { 0, v_range.s_row + 2, v_range.s_col + 1, 0 })
	end)
	if not ok then
		error(tostring(raw_output),2)
	end

	ok, raw_output = pcall(function()
		return vim.fn.setpos("'>", { 0, v_range.e_row, v_range.e_col - 1, 0 })
	end)
	if not ok then
		error(tostring(raw_output),2)
	end

	ok, raw_output = pcall(function()
		vim.cmd("normal! gv")
	end)
	if not ok then
		error(tostring(raw_output),2)
	end

	return nil
end

--- Function: Detects injected language at the cursor position and begins
--- editing supported languages according to configured preferences.
--- Creates a child buffer with an NJChild object that stores config information
--- for itself and information to replace text in the parent buffer. It also
--- appends the child buffer handle to an NJParent object in the parent buffer.
---@return nil|string err Erring, if applicable.
M.edit = function()
	---@type boolean, any|nil, string|nil, string|nil, string|nil, integer|nil
	local ok, raw_output, err, inj_node_text, inj_node_lang, parent_bufnr

	ok, raw_output = pcall(function()
		return vim.api.nvim_get_current_buf()
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	parent_bufnr = raw_output
	if not parent_bufnr then
		error("ninjection.edit() error: Could not retrieve current buffer handle.", 2)
	end
	---@cast parent_bufnr integer

	---@type NJNodeTable|nil
	local inj_node_info
	inj_node_info, err = nts.get_node_table(M.cfg.inj_lang_query, M.cfg.file_lang)
	if not inj_node_info then
		if not M.cfg.suppress_warnings then
			vim.notify("ninjection.edit() waring: Failed to get injected node " ..
			"information: " .. tostring(err), vim.log.levels.WARN)
		end
		return nil
	end
	---@cast inj_node_info NJNodeTable

	if inj_node_info.node then
		ok, raw_output = pcall(function()
			return ts.get_node_text(inj_node_info.node, parent_bufnr)
		end)
		if not ok then
			error(tostring(raw_output),2)
		end
		inj_node_text = raw_output
		if not inj_node_text or inj_node_text == "" then
			vim.notify("ninjection.edit() warning: Failed to get injected node text " ..
				"calling vim.treesitter.get_node_text()", vim.log.levels.WARN)
			return nil
		end
	end
	---@cast inj_node_text string

	if not inj_node_info.range then
		vim.notify("ninjection.edit() warning: Failed to retrieve valid range " ..
			"for injected content calling get_node_table().", vim.log.levels.WARN)
		return nil
	end

	inj_node_lang, err = nts.get_inj_lang(M.cfg.inj_lang_query, parent_bufnr,
		M.cfg.file_lang)
	if not inj_node_lang or inj_node_lang == "" then
		error("ninjection.edit() error: Failed to get injected node language " ..
			"calling get_inj_lang(): " .. tostring(err), 2)
	end
	---@cast inj_node_lang string

	ok, raw_output = pcall(function()
		return vim.fn.setreg(M.cfg.register, inj_node_text)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	vim.notify("ninjection.edit(): Copied injected content text to register: " ..
	M.cfg.register, vim.log.levels.INFO)

	ok, raw_output = pcall(function()
		return vim.api.nvim_win_get_cursor(0)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	---@type integer[]|nil
	local parent_cursor = raw_output
	if not parent_cursor then
		if not M.cfg.suppress_warnings then
			vim.notify("ninjection.edit() warning: No cursor position returned from " ..
			"vim.api.nvim_win_get_cursor(0)", vim.log.levels.WARN)
		end
		-- Don't return on failed cursor
	end
	---@cast parent_cursor integer[]

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_name(0)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	---@type string|nil
	local parent_name = raw_output
	if not parent_name or parent_name == "" then
		if not M.cfg.suppress_warnings then
			vim.notify("ninjection.edit() warning: No name returned from " ..
			"vim.api.nvim_buf_get_name(0)", vim.log.levels.WARN)
		end
		return nil
	end
	---@cast parent_name string

	---@type string|nil
	local root_dir
	-- Try getting the first workspace folder.
	ok, raw_output = pcall(function()
		return vim.lsp.buf.list_workspace_folders()[1]
	end)
	if ok and raw_output and raw_output ~= "" then
		root_dir = raw_output
	else
		-- Fall back to the current working directory.
		local nested_ok, nested_raw_output = pcall(function()
			return vim.fn.getcwd()
		end)
		if nested_ok and nested_raw_output and nested_raw_output ~= "" then
			root_dir = nested_raw_output
		else
			error("ninjection.edit() error: Could not retrieve workspace directory " ..
				"or current directory.\nvim.lsp.buf.list_workspace_folders()[1] error: " ..
			tostring(raw_output) .. "\nvim.fn.getcwd() error: " ..
			tostring(nested_raw_output),2)
		end
	end
	if not root_dir or root_dir == "" then
		error("ninjection.edit() error: Unknown error setting root_dir",2)
	end
	---@cast root_dir string

	---@type integer|nil
	local child_bufnr = vim.api.nvim_create_buf(true, true)
	if not child_bufnr then
		error("ninjection.edit() error: Failed to create a child buffer.",2)
	end
	---@cast child_bufnr integer

	-- Setup the child buffer
	ok, raw_output = pcall(function()
		return vim.api.nvim_set_current_buf(child_bufnr)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end

	ok, raw_output = pcall(function()
		return vim.cmd('normal! "zp')
	end)
	if not ok then
		error(tostring(raw_output),2)
	end

	ok, raw_output = pcall(function()
		return vim.cmd("file " .. parent_name .. ":" .. inj_node_lang .. ":" ..
		child_bufnr)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end

	ok, raw_output = pcall(function()
		return vim.cmd("set filetype=" .. inj_node_lang)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end

	-- Preserve indentation after creating and pasting buffer contents, but before
	-- autoformatting.
	---@type NJIndents|nil
	local parent_indents
	if M.cfg.preserve_indents then
		parent_indents, err = util.get_indents(0)
		if not parent_indents then
			if not M.cfg.suppress_warnings then
				vim.notify("ninjection.edit() warning: Unable to preserve indentation " ..
				"with get_indents(): " .. tostring(err), vim.log.levels.WARN)
			end
			-- Don't return early on indentation errors
		end
		---@cast parent_indents NJIndents
	end
	-- Initialized to 0 if unset
	if not parent_indents then
		parent_indents = {t_indent = 0, b_indent = 0, l_indent = 0}
		---@cast parent_indents NJIndents
	end

	ok, raw_output = pcall(function()
		return vim.cmd("doautocmd FileType " .. inj_node_lang)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end

	--- We want to keep the same relative cursor position in the child buffer as
	--- in the parent buffer.
	---@type integer[]|nil
	local offset_cur
	-- Assuming autoformat will remove any existing indents, we need to offset
	-- the cursor for the removed indents.
	if M.cfg.preserve_indents and M.cfg.auto_format then
		---@type integer
		local relative_row = parent_cursor[1] - inj_node_info.range.s_row
		relative_row = math.max(1, relative_row)
		print("DEBUG relative_row: ", relative_row)
		---@type integer
		local relative_col = parent_cursor[2] - parent_indents.l_indent
		relative_col = math.max(0, relative_col)
		print("DEBUG relative_col: ", relative_col)
		offset_cur = { relative_row, relative_col}
	else
		---@type integer
		local relative_row = parent_cursor[1] - inj_node_info.range.s_row
		relative_row = math.max(1, relative_row)
		offset_cur = { relative_row, parent_cursor[2] }
	end
	---@cast offset_cur integer[]
	print("DEBUG: starting row: ", inj_node_info.range.s_row)
	print("DEBUG offset_cur: ", vim.inspect(offset_cur))

	ok, raw_output = pcall(function()
		return vim.api.nvim_win_set_cursor(0, offset_cur)
	end)
	if not ok then
		if not M.cfg.suppress_warnings then
		err = tostring(raw_output)
			vim.notify("ninjection.edit() warning: Calling vim.api.nvim_win_set_cursor(0" ..
			", {(" .. tostring(offset_cur) .. "})" .. "\n" .. err, vim.log.levels.WARN)
			-- Don't return early on cursor set error
		end
	end

	if M.cfg.auto_format then
		ok, raw_output = pcall(function()
			return vim.cmd("lua " .. M.cfg.format_cmd)
		end)
		if not ok then
			if not M.cfg.suppress_warnings then
				err = tostring(raw_output)
				vim.notify("ninjection.edit() warning: Calling vim.cmd(\"lua \"" ..
				M.cfg.format_cmd .. ")\n" .. err, vim.log.levels.WARN)
				-- Don't return early on auto-format error
			end
		end
	end

	---@type NJLspStatus|nil
	local lsp_status
	lsp_status, err = util.start_lsp(inj_node_lang, root_dir)
	if not lsp_status then
		if not M.cfg.suppress_warnings then
			err = tostring(err) ---@cast err string
			vim.notify("ninjection.edit() warning: starting LSP " ..err,
			vim.log.levels.WARN)
			-- Don't return early on LSP failure
		end
	end

	-- Track parent, child buffer relations, in the event multiple child buffers
	-- are opened for the same injected content.
	-- Retrieve the existing ninjection table or initialize a new one
	---@type NJParent
	local parent_ninjection
	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_var(parent_bufnr, "ninjection")
	end)
	if ok then
		parent_ninjection = raw_output
	else
		err = tostring(raw_output)
		if err:find("Key not found: ninjection") then
			parent_ninjection = { children = {} }
		else
			error(err)
		end
	end
	parent_ninjection.children = parent_ninjection.children or {}

	-- Append the new child_bufnr to the children array.
	table.insert(parent_ninjection.children, child_bufnr)

	-- Write it back to the buffer variable.
	vim.api.nvim_buf_set_var(parent_bufnr, "ninjection", parent_ninjection)

	---@type NJChild
	local child_ninjection = {
		bufnr = child_bufnr,
		root_dir = root_dir,
		parent_bufnr = parent_bufnr,
		parent_indents = parent_indents,
		parent_range = {
			s_row = inj_node_info.range.s_row,
			s_col = inj_node_info.range.s_col,
			e_row = inj_node_info.range.e_row,
			e_col = inj_node_info.range.e_col,
		},
	}

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_set_var(child_bufnr, "ninjection", child_ninjection)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end

	return nil
end


--- Function: Replace the original injected language text in the parent buffer
--- with the current buffer text. This state is stored by in the vim.b.ninjection
--- table as an NJParent table in the child, and NJChild table indexed by the
--- child bufnr in the parent. This relationship is validated before replacing.
---@return nil|string err Returns err string, if applicable
M.replace = function()
	---@type boolean, any|nil, string|nil, NJChild|nil, NJParent|nil, integer|nil
	local ok, raw_output, err, nj_child_b, nj_parent_b, this_bufnr

	ok, raw_output = pcall(function()
		return vim.api.nvim_get_current_buf()
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	this_bufnr = raw_output
	if not this_bufnr then
		error("ninjection.replace() error: Could not retrieve a buffer handle " ..
		"calling vim.api.nvim_get_current_buf().",2)
	end
	---@cast this_bufnr integer

	-- We need to validate that this buffer has a parent buffer, and that the
	-- parent buffer has this buffer as a child.
	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_var(this_bufnr, "ninjection")
	end)
	if not ok then
		err = tostring(raw_output)
		if err:find("Key not found: ninjection") then
			if not M.cfg.suppress_warnings then
				vim.notify("ninjection.replace() warning: This buffer is not a valid " ..
				"ninjection buffer.", vim.log.levels.WARN)
			end
			return nil
		end
	end
	nj_child_b = raw_output
	if not nj_child_b.parent_bufnr then
		error("ninjection.replace() error: Could not retrieve valid parent buffer " ..
		"for this buffer.", 2)
	end
	---@cast nj_child_b NJChild

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_var(nj_child_b.parent_bufnr, "ninjection")
	end)
	if not ok then
		err = tostring(raw_output)
		if err:find("Key not found: ninjection") then
			error("ninjection.replace() error: This buffer appears to be an orphan. " ..
			"The recorded parent has no ninjection table.",2)
		end
		error(err,2)
	end
	nj_parent_b = raw_output
	if not vim.tbl_contains(nj_parent_b.children, this_bufnr) then
		error("ninjection.replace() error: The recorded parent buffer has no " ..
			"record of this buffer.", 2)
	end
	---@cast nj_parent_b NJParent

	ok, raw_output = pcall(function()
		return vim.api.nvim_win_get_cursor(0)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	---@type integer[]|nil
	local this_cursor = raw_output
	if not this_cursor then
		if not M.cfg.suppress_warnings then
			vim.notify("ninjection.replace() warning: No child cursor values returned " ..
			"by vim.api.nvim_win_get_cursor(0)", vim.log.levels.WARN)
		end
	end
	---@cast this_cursor integer[]

	if not nj_child_b.parent_range then
		error("ninjection.replace() error: missing parent buffer range values. " ..
		"Cannot sync changes.",2)
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_lines(0, 0, -1, false)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end
	---@type string[]|nil
	local rep_text = raw_output
	if not rep_text or rep_text == "" then
		if not M.cfg.suppress_warnings then
			vim.notify("ninjection.replace() warning: No replacement text returned " ..
			"by vim.api.nvim_buf_get_lines()", vim.log.levels.WARN)
		end
		return nil
	end
	---@cast rep_text string[]

	if M.cfg.preserve_indents then
			raw_output, err = util.restore_indents(rep_text, nj_child_b.parent_indents)
			if err then
				if not M.cfg.suppress_warnings then
					vim.notify("ninjection.replace() warning: util.restore_indents() " ..
					"could not restore indents: " .. err,
					vim.log.levels.WARN)
				end
			else
				rep_text = raw_output
			end
			---@cast rep_text string[]
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_set_text(
			nj_child_b.parent_bufnr,
			nj_child_b.parent_range.s_row,
			nj_child_b.parent_range.s_col,
			nj_child_b.parent_range.e_row,
			nj_child_b.parent_range.e_col,
			rep_text
		)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end


	ok, raw_output = pcall(function()
		return vim.cmd("bdelete!")
	end)
	if not ok then
		error(tostring(raw_output),2)
	end

	-- Remove the child entry in the parent after deleting the buffer
	nj_parent_b.children[this_bufnr] = nil
	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_set_var(nj_child_b.parent_bufnr, "ninjection",
			nj_parent_b)
	end)
	if not ok then
		err = tostring(raw_output)
		if not M.cfg.suppress_warnings then
			vim.notify("ninjection.replace() warning: could not remove child buffer " ..
			"entry from parent buffer after deleting buffer." .. err, vim.log.levels.WARN)
		end
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_set_current_buf(nj_child_b.parent_bufnr)
	end)
	if not ok then
		error(tostring(raw_output),2)
	end

	-- Reset the cursor to the same relative position in the parent buffer
	---@type integer[]|nil
	local pos
	if M.cfg.preserve_indents then
		pos = { this_cursor[1] + nj_child_b.parent_range.s_row + 1,
			this_cursor[2] + nj_child_b.parent_indents.l_indent }
	else
		pos = { this_cursor[1] + nj_child_b.parent_range.s_row, this_cursor[2] }
	end
	---@cast pos integer[]
	ok, raw_output = pcall(function()
		return vim.api.nvim_win_set_cursor(0, pos)
	end)
	if not ok then
		err = tostring(raw_output)
		if not M.cfg.suppress_warnings then
			vim.notify("ninjection.replace() warning: could not restore cursor " ..
			"position in the parent buffer." .. err, vim.log.levels.WARN)
		end
	end
end

return M
