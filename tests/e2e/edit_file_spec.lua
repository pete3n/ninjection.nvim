package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path
require("helpers.init")

local eq = assert.are.same
local nj = require("ninjection")

print(vim.inspect(vim.opt.rtp:get()))

describe("ninjection.edit integration test #e2e #edit", function()
	it("validates injected content in edit buffer", function()
		vim.cmd("edit tests/ft/nix/lua.nix")
		local buf_content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		print("Buffer content:", vim.inspect(buf_content))
		vim.api.nvim_win_set_cursor(0, { 5, 7 })
		nj.edit()
		local buf = vim.api.nvim_get_current_buf()
		buf_content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local expected = {
			"      local lua_content",
			"      local more_lua_content",
		}
		print("Buffer content: " .. vim.inspect(buf_content))

		eq(expected, buf_content)
	end)
end)
