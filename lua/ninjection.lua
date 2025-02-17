local M = {}

local ts = require("vim.treesitter")
local rel = require("ninjection.relation")

--- @type ninjection.util
local util = require("ninjection.util")

--- @type ninjection.treesitter
local nts = require("ninjection.treesitter")

if vim.fn.exists(":checkhealth") == 2 then
	require("ninjection.health").check()
end

M.cfg = {
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

	-- TODO: Implement working register option
	register = "z",

	-- Injected language query string
	inj_lang_query = [[
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

--- Function: Identify and select injected content text in visual mode
---@return nil
M.select = function()
	---@type string|nil
	local err
	---@type boolean, integer
	local ok, bufnr, raw_output
	ok, raw_output = pcall(function()
		return vim.api.nvim_get_current_buf()
	end)
	if not ok then
		vim.notify("ninjection.select(): nvim_get_current_buf failed.",
			vim.log.levels.WARN)
		err = tostring(raw_output)
		if err then
			vim.api.nvim_err_write(err)
		end
		return nil
	end
	bufnr = raw_output

	---@type table|nil
	local info
	info, err = nts.get_node_table(M.cfg.inj_lang_query, bufnr)
	if not info then
		vim.notify("ninjection.select(): get_node_table() returned a nil value.",
			vim.log.levels.INFO)
		if err then
			vim.api.err.nvim_err_write(err)
			return nil
		end
		return nil
	end

	if not info.node then
		vim.notify("ninjection.select(): get_node_table() returned a nil node.",
			vim.log.levels.info)
		return nil
	end
	local vs_row, vs_col, ve_row, ve_col = nts.get_visual_range(info.node, bufnr)
	-- This assumes a injected code block style of
	-- assignment = # inj_lang
	-- ''
	-- 		injected.content
	-- '';

	ok, raw_output = pcall(function()
		return vim.fn.setpos("'<", { 0, vs_row + 2, vs_col + 1, 0 })
	end)
	if not ok then
		vim.notify("ninjection.select(): Error setting beginning mark.", vim.log.levels.WARN)
		err = tostring(raw_output)
		if err then
			vim.api.nvim_err_write(err)
			return nil
		end
		return nil
	end

	ok, raw_output = pcall(function()
		vim.fn.setpos("'>", { 0, ve_row, ve_col - 1, 0 })
	end)
	if not ok then
		vim.notify("ninjection.select(): Error setting ending mark.", vim.log.levels.WARN)
		err = tostring(raw_output)
		if err then
			vim.api.nvim_err_write(err)
			return nil
		end
		return nil
	end

	ok, raw_output = pcall(function()
		vim.cmd("normal! gv")
	end)
	if not ok then
		vim.notify("ninjection.select(): Error setting visual mode.", vim.log.levels.WARN)
		err = tostring(raw_output)
		if err then
			vim.api.nvim_err_write(err)
			return nil
		end
		return nil
	end
end

--- Function: Detects injected language at the cursor position and begins
--- editing supported languages according to config preferences
---@return nil
M.edit = function()
	---@type string|nil
	local inj_node_text, inj_node_lang, err
	---@type table|nil
	local original_indents

	---@type boolean, integer
	local ok, parent_bufnr, raw_output
	ok, raw_output = pcall(function()
		return vim.api.nvim_get_current_buf()
	end)
	if not ok then
		---@type string
		err = tostring(raw_output)
		vim.api.nvim_err_writeln(err)
		return nil
	end
	parent_bufnr = raw_output

	---@type table|nil
	local inj_node
	inj_node, err = nts.get_node_table(M.cfg.inj_lang_query, parent_bufnr)
	if not inj_node then
		vim.notify("ninjection.edit(): Failed to get injected node information " ..
			"calling get_node_table()", vim.log.levels.WARN)
		if err then
			vim.api.nvim_err_writeln(err)
		end
		return nil
	end
	---@cast inj_node table

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
		if not inj_node_text then
			vim.notify("ninjection.edit(): Failed to get injected node text " ..
				"calling vim.treesitter.get_node_text()", vim.log.levels.WARN)
			return nil
		end
	end

	if not inj_node.range then
		vim.notify("ninjection.edit(): Failed to retrieve valid range for injected " ..
			" content calling get_node_table().")
		return nil
	end

	inj_node_lang, err = nts.get_inj_lang(M.cfg.inj_lang_query, parent_bufnr)
	if not inj_node_lang then
		vim.notify("ninjection.edit(): Failed to get injected node language " ..
			"calling get_inj_lang()", vim.log.levels.WARN)
		if err then
			vim.api.nvim_err_writeln(err)
		end
		return nil
	end

	if M.cfg.preserve_indents then
		original_indents, err = util.get_indents(0)
		-- Border preservation is not a halting error
		if not original_indents then
			vim.notify("ninjection.edit(): Unable to preserve indentation.")
			if err then
				vim.notify(err)
			end
		end
	end

	vim.fn.setreg(M.cfg.register, inj_node_text)
	vim.notify("ninjection.edit(): Copied injected content text to register: " .. M.cfg.register)

	---@type integer[]
	local cur = vim.api.nvim_win_get_cursor(0)
	---@type { row: integer, col: integer }
	local parent_cursor = { row = cur[1], col = cur[2] }
	---@type string
	local parent_mode = vim.fn.mode()
	---@type string
	local parent_name = vim.api.nvim_buf_get_name(0)
	---@type string
	local parent_root_dir = vim.lsp.buf.list_workspace_folders()[1] or vim.fn.getcwd()
	---@type integer
	local child_bufnr = vim.api.nvim_create_buf(true, true)
	if not child_bufnr then
		vim.notify("ninjection.edit(): Failed to create a child buffer.")
		return nil
	end

	-- Track parent, child buffer relations, in the event multiple child buffers
	-- are opened for the same injected content.
	rel.add_inj_buff(parent_bufnr, child_bufnr, inj_node.range, parent_cursor, parent_mode)

	-- Setup the child buffer
	vim.api.nvim_set_current_buf(child_bufnr)
	vim.cmd('normal! "zp')

	vim.cmd("file " .. parent_name .. ":" .. inj_node_lang .. ":" .. child_bufnr)
	vim.cmd("set filetype=" .. inj_node_lang)
	vim.cmd("doautocmd FileType " .. inj_node_lang)

	vim.api.nvim_win_set_cursor(0, { (parent_cursor.row - inj_node.range[1]), parent_cursor.col })

	print("auto_format:", M.cfg.auto_format)
	if M.cfg.auto_format then
		vim.notify("ninjection.edit(): Auto formatting")
		vim.cmd("lua " .. M.cfg.format_cmd)
	end

	util.start_lsp(inj_node_lang, parent_root_dir)

	vim.b.ninjection = {
		range = inj_node.range,
		parent_bufnr = parent_bufnr,
		parent_cursor = parent_cursor,
		parent_mode = parent_mode,
		parent_root_dir = parent_root_dir,
		parent_indents = original_indents,
	}
end

--- Replace the original injected language text in the parent buffer with the
--- edited text in the child buffer.
---@return nil
M.replace = function()
	---@type string|nil
	local err
	---@type table|nil
	local njb = vim.b.ninjection
	---@type boolean, integer[]
	local ok, child_cursor, raw_output
	ok, raw_output = pcall(function()
		return vim.api.nvim_win_get_cursor(0)
	end)
	if not ok then
		err = tostring(raw_output)
		vim.api.nvim_err_writeln(err)
		return nil
	end
	child_cursor = raw_output

	if not (njb.parent_bufnr and njb.range) then
		vim.api.nvim_err_writeln("ninjection.replace(): missing injection " ..
			"information. Cannot sync changes.")
		return nil
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_lines(0, 0, -1, false)
	end)
	if not ok then
		vim.notify("ninjection.replace(): Error getting buffer text.")
		err = tostring(raw_output)
		if err then
			vim.api.nvim_err_writeln(err)
		end
		return nil
	end
	---@type string[]
	local rep_text = raw_output
	if M.cfg.preserve_indents then
		rep_text = util.restore_indents(rep_text, njb.parent_borders)
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_set_text(
			njb.parent_bufnr,
			njb.range[1],
			njb.range[2],
			njb.range[3],
			njb.range[4],
			rep_text
		)
	end)
	if not ok then
		vim.notify("ninjection.replace(): Error setting buffer text.")
		err = tostring(raw_output)
		if err then
			vim.api.nvim_err_writeln(err)
		end
		return nil
	end

	ok, raw_output = pcall(function()
		return vim.cmd("bdelete!")
	end)
	if not ok then
		vim.notify("ninjection.replace(): Error deleting buffer.")
		err = tostring(raw_output)
		if err then
			vim.api.nvim_err_writeln(err)
		end
		return nil
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_set_current_buf(njb.parent_bufnr)
	end)
	if not ok then
		vim.notify("ninjection.replace(): Error switching to parent buffer.")
		err = tostring(raw_output)
		if err then
			vim.api.nvim_err_writeln(err)
		end
		return nil
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_win_set_cursor(0, njb.parent_cursor)
	end)
	if not ok then
		vim.notify("ninjection.replace(): Error resetting cursor.")
		err = tostring(raw_output)
		if err then
			vim.api.nvim_err_writeln(err)
		end
		return nil
	end
end

return M
