package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path
require("helpers.init")

local eq = assert.are.same
local nj = require("ninjection")

describe("ninjection.format integration test #e2e #format", function()
	it("validates injected content after formatting buffer", function()
		vim.cmd("edit tests/ft/nix/lua.nix")
		local buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_set_option_value("swapfile", false, { buf = buf })

		local buf_content = vim.api.nvim_buf_get_lines(0, 9, 15, false)
		print("Buffer content:", vim.inspect(buf_content))
		vim.api.nvim_win_set_cursor(0, { 11, 7 })
		nj.format()
		vim.wait(3000) -- TODO: Replace with appropriate configuration timing
		buf = vim.api.nvim_get_current_buf()
		buf_content = vim.api.nvim_buf_get_lines(buf, 9, 15, false)
		local expected = {
			"    ''",
			"      do",
			"        local lua_content",
			"        local more_lua_content",
			"      end",
			"    '';",
		}
		print("Buffer content: " .. vim.inspect(buf_content))

		eq(expected, buf_content)
	end)
end)
