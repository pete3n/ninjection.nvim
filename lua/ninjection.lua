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
	preserve_indents = false, -- Re-apply indents from the parent buffer.
	-- This option should be used in conjunction with auto_format because
	-- This will re-apply indents that auto_format normally removes.
	-- If you don't remove them, then they will be re-applied which will increase
	-- the original indenation.
	auto_format = false, -- Format the new child buffer with the provided command
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
      M.cfg.lsp_map[k] = v  -- Override defaults
    end
  end
end

M.select = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local node = M.get_node_range(M.cfg.inj_lang_query)
  if not node then
    print("No injection content found at the cursor.")
    return
  end

  local vs_row, vs_col, ve_row, ve_col = nts.get_visual_range(node, bufnr)
	-- This assumes a injected code block style of
	-- assignment = # inj_lang
	-- ''
	-- 		injected.content
	-- '';
  vim.fn.setpos("'<", {0, vs_row + 2, vs_col + 1, 0})
  vim.fn.setpos("'>", {0, ve_row, ve_col - 1, 0})
  vim.cmd("normal! gv")
end

--- Function: Detects injected language at the cursor position and begins
--- editing supported languages according to config preferences
---@return nil
M.edit = function()
	---@type string
	local node_text
	---@type integer
	local parent_bufnr = vim.api.nvim_get_current_buf()
	---@type table|nil
	local inj_node, err = nts.get_node_info(M.cfg.inj_lang_query, parent_bufnr)
	if not inj_node then
		vim.notify("ninjection.edit(): failed to get injected node information.")
		if err then
			vim.api.nvim_err_writeln(err)
		end
	end
	---@cast inj_node table

	if inj_node.node then
		---@type boolean, string
		local ok, raw_output
		ok, raw_output = pcall(function()
			return ts.get_node_text(inj_node.node, parent_bufnr)
		end)
		if not ok then
			---@string
			err = tostring(raw_output)
			vim.api.nvim_err_writeln(err)
			return nil
		end
		node_text = raw_output
		if not node_text then
			vim.notify("ninjection.edit(): Could not get injection block text.")
			return nil
		end
	end

	if not inj_node.lang then
		if inj_node.err then
			err = inj_node.err
			vim.notify(err)
			return nil
		end

		vim.notify("ninjection.edit(): Could not determined injected language " ..
			"for this block, for an undetermined reason.")
		return nil
	end

	vim.fn.setreg("z", node_text)
	vim.notify("Copied injection block text to register 'z'.")

	-- Save parent's cursor position and mode before switching buffers.
  local cur = vim.api.nvim_win_get_cursor(0)
  local parent_cursor = { row = cur[1], col = cur[2] }
  local parent_mode = vim.fn.mode()
	local parent_name = vim.api.nvim_buf_get_name(0)
	local parent_root_dir = vim.lsp.buf.list_workspace_folders()[1] or vim.fn.getcwd()

	local child_bufnr = vim.api.nvim_create_buf(true, true)
	if not child_bufnr then
		print("Failed to create a child buffer.")
		return
	end

	if not inj_node.range then
		vim.notify("ninjection.edit(): Failed to retrieve valid range for injected content")
		return nil
	end

	rel.add_inj_buff(parent_bufnr, child_bufnr, inj_node.range, parent_cursor, parent_mode)

	vim.api.nvim_set_current_buf(child_bufnr)
	vim.cmd('normal! "zp')
	local original_borders = util.get_borders()
	vim.cmd('file ' .. parent_name .. ':' .. inj_node.lang .. ':' .. child_bufnr)
	vim.cmd("set filetype=" .. inj_node.lang)
	vim.cmd("doautocmd FileType " .. inj_node.lang)

	vim.api.nvim_win_set_cursor(0, {(parent_cursor.row - inj_node.range.s_row), parent_cursor.col})

	util.start_lsp(inj_node.lang, parent_root_dir)

	if M.cfg.auto_format then
		vim.cmd("lua " .. M.cfg.format_cmd)
	end

	vim.b.ninjection = {
		range = { s_row = inj_node.range.s_row, s_col = inj_node.range.s_col,
			e_row = inj_node.range.e_row, e_col = inj_node.range.e_col },
		parent_bufnr = parent_bufnr,
		parent_cursor = parent_cursor,
		parent_mode = parent_mode,
		prent_root_dir = parent_root_dir,
		parent_borders = original_borders,
	}

end

--- Replace the original injected language text in the parent buffer with the
--- edited text in the child buffer.
---@return nil
M.replace = function()
  local njb = vim.b.ninjection
  local child_cursor = vim.api.nvim_win_get_cursor(0)

  if not (njb and njb.parent_bufnr and njb.range) then
		vim.api.nvim_err_writeln("ninjection ERROR: No injection info found in this buffer." ..
			" Cannot sync changes.")
    return nil
  end

  local rep_text = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	if M.cfg.preserve_indents then
		rep_text = util.restore_borders(vim.api.nvim_buf_get_lines(0, 0, -1, false),
			njb.parent_borders)
	end

  vim.api.nvim_buf_set_text(njb.parent_bufnr, njb.range.s_row, njb.range.s_col,
		njb.range.e_row, njb.range.e_col, rep_text)
	vim.cmd("bdelete!")

	vim.api.nvim_set_current_buf(njb.parent_bufnr)
	vim.api.nvim_win_set_cursor(0, child_cursor)
end

return M
