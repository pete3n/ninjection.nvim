package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

local eq = assert.are.same
local nj = require("ninjection")

describe("ninjection.edit integration test #e2e #lua #edit", function()
	it("validates injected content in edit buffer", function()
		vim.cmd("noswapfile")
		vim.cmd("edit /ninjection/tests/ft/nix/lua_edit.nix")

		local p_content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		print("Buffer content before edit:\n" .. table.concat(p_content, "\n"))
		vim.api.nvim_win_set_cursor(0, { 5, 7 })
		nj.edit()
		local child_buf = vim.api.nvim_get_current_buf()
		local c_content = vim.api.nvim_buf_get_lines(child_buf, 0, -1, false)
		local expected = {
			"local lua_content",
			"local more_lua_content",
			"for i = 1, 10, 1 do",
			"  lua_content = lua_content + 1",
			"end",
		}
		print("Buffer content after edit:\n" .. table.concat(c_content, "\n"))
		eq(expected, c_content)
		vim.cmd("bdelete!")
	end)
end)
