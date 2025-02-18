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

	-- TODO: Implement other scratch buffer types, currently only std
	buffer_styles = { "std", "popup", "v_split", "h_split", "tab_r", "tab_l" },
	buffer_style = "std",
	-- TODO: Implement auto-inject on buffer close
	inject_on_close = false,
	register = "z",
	suppress_warnings = false, -- true|false only show critical errors
	-- If ninjection is not functioning properly, ensure this is false to debug

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
		vim.notify("ninjection.select(): Error calling vim.api.nvim_get_current_buf()" ..
			": " .. err, vim.log.levels.ERROR)
		err = tostring(raw_output)
		return err
	end
	bufnr = raw_output
	if not bufnr then
		if M.cfg.suppress_warnings == false then
			vim.notify("ninjection.select(): Could not get current buffer calling " ..
			"vim.api.nvim_get_current_buf()", vim.log.levels.WARN)
		end
		return nil
	end

	node_info, err = nts.get_node_table(M.cfg.inj_lang_query, M.cfg.file_lang)
	if not node_info then
		if M.cfg.suppress_warnings == false then
			vim.notify("ninjection.select(): get_node_table() returned nil.",
			vim.log.levels.WARN)
		end
		if err then
			vim.api.err.nvim_err_write(err)
			return err
		end
		return nil
	end
	if not node_info.node then
		if M.cfg.suppress_warnings == false then
			vim.notify("ninjection.select(): get_node_table() returned a nil node.",
			vim.log.levels.WARN)
		end
		return nil
	end

	---@type NJRange|nil
	local v_range
	v_range, err = nts.get_visual_range(node_info.node, bufnr)
	if not v_range then
		if M.cfg.suppress_warnings == false then
			vim.notify("ninjection.select(): get_visual_range() returned a nil range.",
			vim.log.levels.WARN)
		end
		if err then
			vim.api.err.nvim_err_writeln(err)
			return err
		end
		return nil
	end

	-- Set marks to select ranges with a custom offset
	ok, raw_output = pcall(function()
		return vim.fn.setpos("'<", { 0, v_range.s_row + 2, v_range.s_col + 1, 0 })
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.select(): Error calling vim.fn.setpos(): " .. err,
		vim.log.levels.ERROR)
		vim.api.err.nvim_err_writeln(err)
		return err
	end

	ok, raw_output = pcall(function()
		return vim.fn.setpos("'>", { 0, v_range.e_row, v_range.e_col - 1, 0 })
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.select(): Error calling vim.fn.setpos(): " .. err,
		vim.log.levels.ERROR)
		vim.api.nvim_err_write(err)
		return nil
	end

	ok, raw_output = pcall(function()
		vim.cmd("normal! gv")
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.select(): Error setting visual mode with " ..
		"vim.cmd(\"normal! gv\"): " .. err, vim.log.levels.ERROR)
		vim.api.nvim_err_write(err)
		return err
	end

	return nil
end

--- Function: Detects injected language at the cursor position and begins
--- editing supported languages according to configured preferences.
---@return nil|string err Erring, if applicable.
M.edit = function()
	---@type boolean, any|nil, string|nil, string|nil, string|nil, integer|nil
	local ok, raw_output, err, inj_node_text, inj_node_lang, parent_bufnr

	ok, raw_output = pcall(function()
		return vim.api.nvim_get_current_buf()
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.edit(): Error calling vim.api.nvim_get_current_buf()" ..
		": " .. err, vim.log.levels.ERROR)
		vim.api.nvim_err_writeln(err)
		return err
	end
	parent_bufnr = raw_output
	if not parent_bufnr then
		err = "ninjection.edit(): Error vim.api.nvim_get_current_buf() " ..
		"did not return a buffer handle."
		vim.notify(err, vim.log.levels.ERROR)
		vim.api.nvim_err_writeln(err)
		return err
	end

	---@type NJNodeTable|nil
	local inj_node
	inj_node, err = nts.get_node_table(M.cfg.inj_lang_query, M.cfg.file_lang)
	if not inj_node then
		if M.cfg.suppress_warnings == false then
			vim.notify("ninjection.edit(): Failed to get injected node information " ..
			"calling get_node_table()", vim.log.levels.WARN)
		end
		if err then
			vim.api.nvim_err_writeln(err)
			return err
		end
		return nil
	end
	---@cast inj_node NJNodeTable

	if inj_node.node then
		ok, raw_output = pcall(function()
			return ts.get_node_text(inj_node.node, parent_bufnr)
		end)
		if not ok then
			err = tostring(raw_output)
			vim.api.nvim_err_writeln(err)
			return nil
		end
		inj_node_text = raw_output
		if not inj_node_text or inj_node_text == "" then
			vim.notify("ninjection.edit(): Failed to get injected node text " ..
				"calling vim.treesitter.get_node_text()", vim.log.levels.WARN)
			return nil
		end
	end
	---@cast inj_node_text string

	if not inj_node.range then
		vim.notify("ninjection.edit(): Failed to retrieve valid range for injected " ..
			" content calling get_node_table().")
		return nil
	end

	inj_node_lang, err = nts.get_inj_lang(M.cfg.inj_lang_query, parent_bufnr, M.cfg.file_lang)
	if not inj_node_lang or inj_node_lang == "" then
		vim.notify("ninjection.edit(): Failed to get injected node language " ..
			"calling get_inj_lang()", vim.log.levels.WARN)
		if err then
			vim.api.nvim_err_writeln(err)
		end
		return nil
	end
	---@cast inj_node_lang string

	---@type NJIndents|nil
	local parent_indents
	if M.cfg.preserve_indents then
		parent_indents, err = util.get_indents(0)
		if not parent_indents then
			-- Don't return early on indentation errors
			if cfg.suppress_warnings == false then
				vim.notify("ninjection.edit(): Unable to preserve indentation by " ..
				"calling get_indents()", vim.log.levels.WARN)
			end
			if err then
				vim.api.nvim_err_writeln(err)
			end
		end
		---@cast parent_indents NJIndents
	end
	-- Initialized to 0 if unset
	if not parent_indents then
		parent_indents = {t_indent = 0, b_indent = 0, l_indent = 0}
		---@cast parent_indents NJIndents
	end

	ok, raw_output = pcall(function()
		return vim.fn.setreg(M.cfg.register, inj_node_text)
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.edit(): Error calling vim.fn.setreg(): " .. err,
		vim.log.levels.ERROR)
		return err
	end
	vim.notify("ninjection.edit(): Copied injected content text to register: " ..
	M.cfg.register, vim.log.levels.INFO)

	ok, raw_output = pcall(function()
		return vim.api.nvim_win_get_cursor(0)
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.edit(): Error calling vim.api.nvim_win_get_cursor(0): " ..
		err, vim.log.levels.ERROR)
		return err
	end
	---@type integer[]|nil
	local cur = raw_output
	if not cur then
		if M.cfg.suppress_warnings == false then
			vim.notify("ninjection.edit(): No cursor position returned from " ..
			"vim.api.nvim_win_get_cursor(0)", vim.log.levels.WARN)
		end
		return nil
	end
	---@cast cur integer[]
	---@type { row: integer, col: integer }
	local parent_cursor = { row = cur[1], col = cur[2] }

	ok, raw_output = pcall(function()
		return vim.fn.mode()
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.edit(): Error calling vim.fn.mode(): " ..
		err, vim.log.levels.ERROR)
		return err
	end
	---@type string|nil
	local parent_mode = raw_output
	if not parent_mode or parent_mode == "" then
		if M.cfg.suppress_warnings == false then
			vim.notify("ninjection.edit(): No mode returned from " ..
			"vim.fn.mode()", vim.log.levels.WARN)
		end
		return nil
	end
	---@cast parent_mode string

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_name(0)
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.edit(): Error calling vim.api.nvim_buf_get_name(0): " ..
		err, vim.log.levels.ERROR)
		return err
	end
	---@type string|nil
	local parent_name = raw_output
	if not parent_name or parent_name == "" then
		if M.cfg.suppress_warnings == false then
			vim.notify("ninjection.edit(): No name returned from " ..
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
			err = "vim.lsp.buf.list_workspace_folders()[1] Error: " ..
			tostring(raw_output) .. "\nvim.fn.getcwd() Error: " ..
			tostring(nested_raw_output)
			vim.notify("ninjection.edit(): Error finding root_dir: " ..
			err, vim.log.levels.ERROR)
			return err
		end
	end
	if not root_dir or root_dir == "" then
		vim.notify("ninjection.edit(): Error unknown error setting root_dir",
		vim.log.levels.ERROR)
		return nil
	end
	---@cast root_dir string

	---@type integer|nil
	local child_bufnr = vim.api.nvim_create_buf(true, true)
	if not child_bufnr then
		vim.notify("ninjection.edit(): Failed to create a child buffer.",
			vim.log.levels.ERROR)
		return nil
	end
	---@cast child_bufnr integer

	-- Setup the child buffer
	ok, raw_output = pcall(function()
		return vim.api.nvim_set_current_buf(child_bufnr)
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.edit(): Error calling vim.api.nvim_set_curent_buf(" ..
		child_bufnr .. ")\n" .. err, vim.log.levels.ERROR)
		return err
	end

	ok, raw_output = pcall(function()
		return vim.cmd('normal! "zp')
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.edit(): Error calling vim.cmd('normal! \"zp')" ..
		err, vim.log.levels.ERROR)
		return err
	end

	ok, raw_output = pcall(function()
		return vim.cmd("file " .. parent_name .. ":" .. inj_node_lang .. ":" ..
		child_bufnr)
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.edit(): Error calling vim.cmd(\"file \")" ..
		parent_name .. ":" .. inj_node_lang .. ":" .. child_bufnr .. "\n" .. err,
		vim.log.levels.ERROR)
		return err
	end

	ok, raw_output = pcall(function()
		return vim.cmd("set filetype=" .. inj_node_lang)
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.edit(): Error calling vim.cmd(\"set filetype=\"" ..
		inj_node_lang .. ")\n" .. err, vim.log.levels.ERROR)
		return err
	end

	ok, raw_output = pcall(function()
		return vim.cmd("doautocmd FileType " .. inj_node_lang)
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.edit(): Error calling vim.cmd(\"doautocmd Filetype \"" ..
		inj_node_lang .. ")\n" .. err, vim.log.levels.ERROR)
		return err
	end

	-- Offset the absolute row in the parent by the relative row in the injected
	-- content range
	ok, raw_output = pcall(function()
		return vim.api.nvim_win_set_cursor(0, {
			(parent_cursor.row - inj_node.range.s_row), parent_cursor.col })
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.edit(): Error calling vim.api.nvim_win_set_cursor(0" ..
		", {(" .. (parent_cursor.row - inj_node.range.s_row) .. "," .. parent_cursor.col ..
		"})" .. "\n" .. err, vim.log.levels.ERROR)
		return err
	end

	if M.cfg.auto_format then
		ok, raw_output = pcall(function()
			return vim.cmd("lua " .. M.cfg.format_cmd)
		end)
		if not ok then
			err = tostring(raw_output)
			vim.notify("ninjection.edit(): Error calling vim.cmd(\"lua \"" ..
			M.cfg.format_cmd .. ")\n" .. err, vim.log.levels.ERROR)
			return err
		end
	end

	---@type NJLspStatus|nil
	local lsp_status
	lsp_status, err = util.start_lsp(inj_node_lang, root_dir)
	if not lsp_status then
		if M.cfg.suppress_warnings == false then
			err = tostring(err) ---@cast err string
			vim.notify("ninjection.edit(): Error starting LSP: " ..err,
			vim.log.levels.WARN)
			-- Don't return on LSP failure
		end
	end

	-- Track parent, child buffer relations, in the event multiple child buffers
	-- are opened for the same injected content.
	---@type NJParent
	vim.api.nvim_buf_set_var(parent_bufnr, "ninjection", {
		children = {
			[child_bufnr] = {
				lang = inj_node_lang
			}
		}
	})

	---@type NJChild
	vim.api.nvim_buf_set_var(child_bufnr, "ninjection", {
		parent = {
			bufnr = parent_bufnr,
			root_dir = root_dir,
			cursor = {
				row = parent_cursor[1],
				col = parent_cursor[2],
			},
			indents = parent_indents,
			mode = parent_mode,
			range = {
				s_row = inj_node.range[1],
				s_col = inj_node.range[2],
				e_row = inj_node.range[3],
				e_col = inj_node.range[4],
			}
		}
	})
end


--- Function: Replace the original injected language text in the parent buffer 
--- with the current text in the child buffer.
--- This state is stored by its vim.b.ninjection table as a NJParent object.
---@return nil|string err Returns err string, if applicable
M.replace = function()
	---@type boolean, any|nil, string|nil, NJChild|nil, integer[]|nil
	local ok, raw_output, err, nj_child_b, child_cursor

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_var(0, "ninjection")
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.replace(): Error calling vim.api.nvim_buf_get_var(): " ..
		err, vim.log.levels.ERROR)
		return err
	end
	nj_child_b = raw_output
	if not nj_child_b or not nj_child_b.parent then
		err = "ninjection.replace(): No valid child object returned from " ..
		"vim.api.nvim_buf_get_var()"
		vim.notify(err, vim.log.levels.ERROR)
		return err
	end
	---@cast nj_child_b NJChild

	---@type boolean, integer[]
	ok, raw_output = pcall(function()
		return vim.api.nvim_win_get_cursor(0)
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.replace(): Error calling vim.api.nvim_win_get_cursor(0): " ..
		err, vim.log.levels.ERROR)
		return err
	end
	child_cursor = raw_output
	if not child_cursor then
		if M.cfg.suppress_warnings == false then
			vim.notify("ninjection.replace(): No child cursor values returned from " ..
			"vim.api.nvim_win_get_cursor(0)", vim.log.levels.WARN)
		end
	end
	---@cast child_cursor integer[]

	if not (nj_child_b.parent.bufnr or nj_child_b.parent.range) then
		vim.notify("ninjection.replace(): missing parent buffer " ..
			"information. Cannot sync changes.", vim.log.levels.ERROR)
		return nil
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_lines(0, 0, -1, false)
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.replace(): Error calling vim.api.nvim_buf_get_lines()" ..
		": " .. err, vim.log.levels.ERROR)
		vim.api.nvim_err_writeln(err)
		return err
	end
	---@type string[]|nil
	local rep_text = raw_output
	if not rep_text or rep_text == "" then
		if M.cfg.suppress_warnings == false then
			vim.notify("ninjection.replace(): No replacement text return from " ..
			"vim.api.nvim_buf_get_lines()", vim.log.levels.WARN)
		end
		return nil
	end
	---@cast rep_text string[]

	if M.cfg.preserve_indents then
			raw_output, err = util.restore_indents(rep_text, nj_child_b.parent.indents)
			if err then
				if M.cfg.suppress_warnings == false then
					vim.notify("ninjection.replace(): Error restoring indents: " .. err,
					vim.log.levels.WARN)
				end
			end
			rep_text = raw_output
			---@cast rep_text string[]
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_set_text(
			nj_child_b.parent.bufnr,
			nj_child_b.parent.range.s_row,
			nj_child_b.parent.range.s_col,
			nj_child_b.parent.range.e_row,
			nj_child_b.parent.range.e_col,
			rep_text
		)
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.replace(): Error replacing parent buffer text: " ..
		err, vim.log.levels.ERROR)
		vim.api.nvim_err_writeln(err)
		return err
	end

	ok, raw_output = pcall(function()
		return vim.cmd("bdelete!")
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.replace(): Error deleting child buffer: " ..
		err, vim.log.levels.ERROR)
		vim.api.nvim_err_writeln(err)
		return err
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_set_current_buf(nj_child_b.parent.bufnr)
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.replace(): Error switching to parent buffer: " ..
		err, vim.log.levels.ERROR)
		vim.api.nvim_err_writeln(err)
		return err
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_win_set_cursor(0, { nj_child_b.parent.cursor.row,
			nj_child_b.parent.cursor.col })
	end)
	if not ok then
		err = tostring(raw_output)
		vim.notify("ninjection.replace(): Error resetting parent cursor: " ..
		err, vim.log.levels.ERROR)
		vim.api.nvim_err_writeln(err)
		return err
	end
end

return M
