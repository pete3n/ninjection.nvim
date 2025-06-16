package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

local eq = assert.are.same
local nj = require("ninjection")

describe("ninjection.replace integration test #e2e #lua #replace", function()
	it("partially replaces injected content in the parent buffer", function()
		vim.cmd("noswapfile")
		vim.cmd("edit /ninjection/tests/ft/nix/lua_replace.nix")

		local parent_buf = vim.api.nvim_get_current_buf()
		local p_before = vim.api.nvim_buf_get_lines(parent_buf, 0, -1, false)
		print("Buffer content before edit:\n" .. table.concat(p_before, "\n"))

		vim.api.nvim_win_set_cursor(0, { 5, 7 }) -- Cursor inside injected block
		nj.edit()
		local child_buf = vim.api.nvim_get_current_buf()

		-- Modify only some of the child lines
		local partial = vim.api.nvim_buf_get_lines(child_buf, 0, -1, false)
		partial[2] = "-- updated second line"
		partial[4] = "  print('Modified loop')"

		vim.api.nvim_buf_set_lines(child_buf, 0, -1, false, partial)

		nj.replace()

		local p_after = vim.api.nvim_buf_get_lines(parent_buf, 0, -1, false)
		print("Buffer content after replace:\n" .. table.concat(p_after, "\n"))

		local expected = {
			"{ }:",
			"{",
			"  injected_content_replace = # lua",
			"    ''",
			"      local lua_content",
			"      -- updated second line",
			"      for i = 1, 10, 1 do",
			"        print('Modified loop')",
			"      end",
			"    '';",
			"}",
		}
		eq(expected, p_after)

		vim.cmd("bdelete!") -- cleanup
	end)
end)
