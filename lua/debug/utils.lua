-- Helper function to print details of the query object.
local function print_query_info(query)
	print("Query object:")
	print(vim.inspect(query))
	if query.captures then
		print("Capture names:")
		for i, name in ipairs(query.captures) do
			print(string.format("  %d: %s", i, name))
		end
	else
		print("No captures found in the query object.")
	end
end

-- Command to test the injection query.
local function test_injected_query()
	local query = injected_lang()
	if query then
		print_query_info(query)
	end
end


-- Command to show the injection block at the cursor.
local function show_injection_block_at_cursor()
	local node, s_row, s_col, e_row, e_col = M.get_cur_blk_coords()
	if node then
		-- Convert the boundaries back to display coordinates (1-indexed).
		print("Cursor is inside an injection block:")
		print(string.format("Start: (%d, %d)   End: (%d, %d)", s_row + 1, s_col + 1, e_row + 1, e_col + 1))
		local text = vim.treesitter.get_node_text(node, vim.api.nvim_get_current_buf())
		print("Block text:")
		print(text)
	else
		print("Cursor is not inside any injection block.")
	end
end

local function show_injection_language_comment_for_block()
	local bufnr = vim.api.nvim_get_current_buf()
	local block_node, block_s_row, _, _, _ = M.get_cur_blk_coords()
	if not block_node then
		print("Cursor is not inside an injection block.")
		return
	end

	local query = M.query.inject()
	if not query then return end

	local parser = vim.treesitter.get_parser(bufnr, "nix")
	if not parser then
		print("No parser available for nix!")
		return
	end
	local tree = parser:parse()[1]
	if not tree then
		print("No syntax tree found!")
		return
	end
	local root = tree:root()

	local candidate = nil
	-- Iterate over all injection.language captures.
	for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
		local capture_name = query.captures[id]
		if capture_name == "injection.language" then
			local s, _, er, _ = node:range()
			-- We assume the comment is entirely above the injection block.
			if er < block_s_row then
				if not candidate or er > candidate.er then
					candidate = { node = node, er = er }
				end
			end
		end
	end

	if candidate then
		local text = vim.treesitter.get_node_text(candidate.node, bufnr)
		print("Injected language comment for this block: " .. text)
	else
		print("No injection.language comment found for the block.")
	end
end

local function show_injection_language_value()
	local bufnr = vim.api.nvim_get_current_buf()
	local query = M.query.inject()
	if not query then
		return
	end

	-- Get the syntax tree's root for the "nix" parser.
	local parser = vim.treesitter.get_parser(bufnr, "nix")
	if not parser then
		print("No parser available for nix!")
		return
	end
	local tree = parser:parse()[1]
	if not tree then
		print("No tree found!")
		return
	end
	local root = tree:root()

	local found = false
	-- Iterate over all captures from the query starting at the root node.
	for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
		local capture_name = query.captures[id]
		if capture_name == "injection.language" then
			local text = vim.treesitter.get_node_text(node, bufnr)
			print("Injection language value: " .. text)
			found = true
		end
	end
	if not found then
		print("No injection.language capture found in the tree.")
	end
end

