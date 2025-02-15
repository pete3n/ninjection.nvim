local M = {}
local rel = require("ninjection.relation")

---@type ninjection.util
local util = require("ninjection.util")
if vim.fn.exists(":checkhealth") == 2 then
	require("ninjection.health").check()
end

M.cfg = {
	-- TODO: Implement other scratch buffer types, currently only std
	buffer_styles = { "std", "popup", "vsplit", "hsplit", "tabr", "tabl" },
	buffer_style = "std",
	-- TODO: Implement indentation preservation
	preserve_l_indent = true,
	-- TODO: Implement auto-inject on buffer close
	inject_on_close = false,

	-- Injected language query string
	ts_query_str = [[
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

M.setup = function(args)
  -- Merge user args with default config
  if args and args.lsp_map then
    for k, v in pairs(args.lsp_map) do
      M.cfg.lsp_map[k] = v  -- Override defaults
    end
  end
end

M.ts_query = function()
	local query = vim.treesitter.query.parse("nix", M.cfg.ts_query_str)
	if not query then
		print("Failed to parse injected language query!")
		return nil
	end
	return query
end

-- Idntify the injected language block at the current cursor position
-- with start and ending coordinates
M.get_cur_blk_coords = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0) -- {row, col} with row 1-indexed, col 0-indexed
	local cur_row = cursor[1] - 1 -- convert to 0-indexed
	local cur_col = cursor[2] -- already 0-indexed

	local query = M.ts_query()
	if not query then
		return nil
	end

	local parser = vim.treesitter.get_parser(bufnr, "nix")
	if not parser then
		print("No parser available for nix!")
		return nil
	end
	local tree = parser:parse()[1]
	if not tree then
		print("No syntax tree found!")
		return nil
	end
	local root = tree:root()

	for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
		local capture_name = query.captures[id]
		if capture_name == "injection.content" then
			local s_row, s_col, e_row, e_col = node:range()
			if
				(cur_row > s_row or (cur_row == s_row and cur_col >= s_col))
				and (cur_row < e_row or (cur_row == e_row and cur_col <= e_col))
			then
				return node, s_row, s_col, e_row, e_col
			end
		end
	end
	return nil
end

-- Determine the injected language for a block range so that new buffer can be set to match it
M.get_blk_lang = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local query = M.ts_query()
	if not query then
		return nil
	end

	local parser = vim.treesitter.get_parser(bufnr, "nix")
	if not parser then
		return nil
	end
	local tree = parser:parse()[1]
	if not tree then
		return nil
	end
	local root = tree:root()

	local _, block_s_row, _, _, _ = M.get_cur_blk_coords()
	if not block_s_row then
		return nil
	end

	local candidate_blk = nil
	for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
		local capture_name = query.captures[id]
		if capture_name == "injection.language" then
			local _, _, e_row, _ = node:range()
			-- Assuming the language comment is entirely above the injection block.
			if e_row < block_s_row then
				if not candidate_blk or e_row > candidate_blk.e_row then
					candidate_blk = { node = node, e_row = e_row }
				end
			end
		end
	end

	if candidate_blk then
		return vim.treesitter.get_node_text(candidate_blk.node, bufnr)
	else
		return nil
	end
end

M.create_child_buffer = function()
	local parent_bufnr = vim.api.nvim_get_current_buf()

	local block_node, s_row, s_col, e_row, e_col = M.get_cur_blk_coords()
	if not block_node then
		print("Cursor is not inside an injection block.")
		return
	end

	local block_text = vim.treesitter.get_node_text(block_node, parent_bufnr)
	if not block_text then
		print("Could not get injection block text.")
		return
	end

	local injected_lang = M.get_blk_lang()
	if not injected_lang then
		print("Could not determine injected language for this block.")
		return
	end

	injected_lang = injected_lang:gsub("^%s*(.-)%s*$", "%1")
	injected_lang = injected_lang:gsub("^#%s*", "")

	vim.fn.setreg("z", block_text)
	print("Copied injection block text to register 'z'.")

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

	local inj_range = { s_row = s_row, s_col = s_col, e_row = e_row, e_col = e_col }
	rel.add_inj_buff(parent_bufnr, child_bufnr, inj_range, parent_cursor, parent_mode)

	vim.api.nvim_set_current_buf(child_bufnr)
	vim.cmd('normal! "zp')
	print("Checking whitespace borders: " .. vim.inspect(util.get_borders()))
	vim.cmd('file ' .. parent_name .. ':' .. injected_lang .. ':' .. child_bufnr)
	vim.cmd("set filetype=" .. injected_lang)
	vim.cmd("doautocmd FileType " .. injected_lang)

	vim.api.nvim_win_set_cursor(0, {(parent_cursor.row - inj_range.s_row), parent_cursor.col})

	util.start_lsp(injected_lang, parent_root_dir)

	vim.b.child_info = {
		parent_bufnr = parent_bufnr,
		inj_range = { s_row = s_row, s_col = s_col, e_row = e_row, e_col = e_col },
		parent_cursor = parent_cursor,
		parent_mode = parent_mode,
		prent_root_dir = parent_root_dir,
	}

end

M.sync_child = function()
  local info = vim.b.child_info
  if not (info and info.parent_bufnr and info.inj_range) then
    print("No injection info found in this buffer. Cannot sync changes.")
    return
  end

  local parent_bufnr = info.parent_bufnr
  local inj_range = info.inj_range  -- expected as { s_row, s_col, e_row, e_col } (1-indexed)

  -- Get the new text from the child (current) buffer.
  local new_text = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Replace the text in the parent buffer in the region corresponding to the injection block.
  vim.api.nvim_buf_set_text(parent_bufnr, inj_range.s_row, inj_range.s_col,
		inj_range.e_row, inj_range.e_col, new_text)
  print("Injection block updated in parent buffer.")

	vim.cmd("bdelete!")
	vim.api.nvim_set_current_buf(parent_bufnr)

	-- Reset the parent buffer cursor where we found it
  local child_cursor = vim.api.nvim_win_get_cursor(0)
  local parent_cursor = child_cursor
  -- The new parent's column is child's column + 1 (to convert 0-indexed to display 1-indexed)

	vim.api.nvim_win_set_cursor(0, parent_cursor)
  print("Parent cursor updated to: " .. vim.inspect(parent_cursor))

end

return M
