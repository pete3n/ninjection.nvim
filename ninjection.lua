-- local debug_u = require 'debug.utils'
local M = {}

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
}

M.ts_query = function()
	local query = vim.treesitter.query.parse("nix", M.cfg.ts_query_str)
	if not query then
		print("Failed to parse injected language query!")
		return nil
	end
	return query
end

-- Identify the injected language block at the current cursor position
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

M.trim_leading_blank_line = function(text)
	local lines = vim.split(text, "\n")
	if #lines > 0 and lines[1]:match("^%s*$") then
		table.remove(lines, 1)
	end
	return table.concat(lines, "\n")
end

M.create_inj_buffer = function()
	local bufnr = vim.api.nvim_get_current_buf()

	local block_node, s_row, s_col, e_row, e_col = M.get_cur_blk_coords()
	if not block_node then
		print("Cursor is not inside an injection block.")
		return
	end

	local block_text = vim.treesitter.get_node_text(block_node, bufnr)
	if not block_text then
		print("Could not get injection block text.")
		return
	end

	block_text = M.trim_leading_blank_line(block_text)

	local injected_lang = M.get_blk_lang()
	if not injected_lang then
		print("Could not determine injected language for this block.")
		return
	end

	injected_lang = injected_lang:gsub("^%s*(.-)%s*$", "%1")
	injected_lang = injected_lang:gsub("^#%s*", "")

	vim.fn.setreg("z", block_text)
	print("Copied injection block text to register 'z'.")

	local new_bufnr = vim.api.nvim_create_buf(false, true)
	if not new_bufnr then
		print("Failed to create a new buffer.")
		return
	end

	vim.api.nvim_set_current_buf(new_bufnr)

	vim.cmd("set filetype=" .. injected_lang)

	vim.cmd('normal! "zp')

	print("Opened new buffer with filetype '" .. injected_lang .. "' and pasted injection block text.")
end

M.setup = function(args)
	vim.api.nvim_create_user_command("NJedit", M.create_inj_buffer, {})
end

return M
