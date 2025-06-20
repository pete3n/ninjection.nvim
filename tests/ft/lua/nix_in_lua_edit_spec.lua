package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

local eq = assert.are.same
local nj = require("ninjection")

describe("ninjection.edit integration test #e2e #nix-lua #edit", function()
	it("validates injected content in edit buffer", function()
		vim.cmd("edit nix_edit.lua")

		local p_content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		if _G.test_debug then
			print("Buffer content before edit:\n" .. table.concat(p_content, "\n"))
		end

		vim.api.nvim_win_set_cursor(0, { 5, 7 })
		nj.edit()
		local child_buf = vim.api.nvim_get_current_buf()
		local c_content = vim.api.nvim_buf_get_lines(child_buf, 0, -1, false)
		local expected = {
			"let",
			"  flake = builtins.getFlake (toString ./.);",
			"in",
			"if builtins.isAttrs flake.outputs.devShells.x86_64-linux.default then",
			"  builtins.attrNames flake.outputs.devShells.x86_64-linux.default",
			"else",
			'  "LEAF"',
		}
		if _G.test_debug then
			print("Buffer content after edit:\n" .. table.concat(c_content, "\n"))
		end
		eq(expected, c_content)
		vim.cmd("bdelete!")
	end)
end)
