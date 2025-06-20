package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

local eq = assert.are.same
local nj = require("ninjection")

describe("ninjection.format integration test #e2e #lua-nix #format", function()
	it("validates injected content after formatting buffer", function()
		vim.cmd("edit /ninjection/tests/ft/nix/lua_format.nix")

		local buf_content = vim.api.nvim_buf_get_lines(0, 3, 9, false)
		if _G.test_debug then
			print("Buffer content before format:\n" .. table.concat(buf_content, "\n"))
		end

		vim.api.nvim_win_set_cursor(0, { 6, 7 })
		nj.format()
		buf_content = vim.api.nvim_buf_get_lines(0, 3, 9, false)

		local expected = {
			"    ''",
			"      do",
			"        local lua_content",
			"        local more_lua_content",
			"      end",
			"    '';",
		}

		if _G.test_debug then
			print("Buffer content after format:\n" .. table.concat(buf_content, "\n"))
		end

		eq(expected, buf_content)
		vim.cmd("bdelete!")
	end)
end)
