local rel = require("ninjection.relation")
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

	-- Save parent's cursor position and mode before switching buffers.
  local cur = vim.api.nvim_win_get_cursor(0) -- returns {row, col} (1-indexed)
  local parent_cursor = { row = cur[1], col = cur[2] }
  local parent_mode = vim.fn.mode()
	local parent_name = vim.api.nvim_buf_get_name(0)

	local child_bufnr = vim.api.nvim_create_buf(true, true)
	if not child_bufnr then
		print("Failed to create a child buffer.")
		return
	end

	vim.api.nvim_set_current_buf(child_bufnr)
	vim.cmd("set filetype=" .. injected_lang)
	vim.cmd('normal! "zp')
	vim.cmd('file ' .. parent_name .. ':' .. injected_lang .. child_bufnr .. ':')

	local inj_range = { s_row = s_row, s_col = s_col, e_row = e_row, e_col = e_col }
	rel.add_inj_buff(parent_bufnr, child_bufnr, inj_range, parent_cursor, parent_mode)

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

  -- Convert the parent's injection range from 1-indexed display to 0-indexed for the API.
  local s_row0 = inj_range.s_row - 1
  local s_col0 = inj_range.s_col - 1
  local e_row0 = inj_range.e_row - 1
  local e_col0 = inj_range.e_col - 1

  -- Replace the text in the parent buffer in the region corresponding to the injection block.
  vim.api.nvim_buf_set_text(parent_bufnr, s_row0, s_col0, e_row0, e_col0, new_text)
  print("Injection block updated in parent buffer.")

  -- Compute the new parent's cursor position.
  -- Get the child buffer's cursor position (child uses display coordinates: row is 1-indexed, col is 0-indexed).
  local child_cursor = vim.api.nvim_win_get_cursor(0)  -- { row, col }
  -- The new parent's row is parent's injection block start row + (child cursor row - 1)
  local new_parent_row = inj_range.s_row + child_cursor[1] - 1
  -- The new parent's column is child's column + 1 (to convert 0-indexed to display 1-indexed)
  local new_parent_col = child_cursor[2] + 1
  local new_parent_cursor = { new_parent_row, new_parent_col }

  -- Try to find a window displaying the parent buffer.
  local wins = vim.fn.win_findbuf(parent_bufnr)
  if #wins > 0 then
    vim.api.nvim_win_set_cursor(wins[1], new_parent_cursor)
    print("Parent cursor updated to: " .. vim.inspect(new_parent_cursor))
  else
    print("No window found for parent buffer; parent's cursor not updated.")
  end
end


M.setup = function(args) end

return M
