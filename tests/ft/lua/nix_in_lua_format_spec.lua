package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

local eq = assert.are.same
local nj = require("ninjection")

describe("ninjection.format integration test #e2e #nix-lua #format", function()
	it("validates injected content after formatting buffer", function()
		vim.cmd("edit /ninjection/tests/ft/lua/nix_format.lua")

		local buf_content = vim.api.nvim_buf_get_lines(0, 1, 9, false)
		if _G.test_debug then
			print("Buffer content before format:\n" .. table.concat(buf_content, "\n"))
		end

		vim.api.nvim_win_set_cursor(0, { 3, 7 })
		nj.format()
		buf_content = vim.api.nvim_buf_get_lines(0, 1, 10, false)

		local expected = {
			"  [[",
			"    let",
			"      flake = builtins.getFlake (toString ./.);",
			"    in",
			"    if builtins.isAttrs flake.outputs.devShells.x86_64-linux.default then",
			"      builtins.attrNames flake.outputs.devShells.x86_64-linux.default",
			"    else",
			'      "LEAF"',
			"  ]]",
		}

		if _G.test_debug then
			print("Buffer content after format:\n" .. table.concat(buf_content, "\n"))
		end

		eq(expected, buf_content)
		vim.cmd("bdelete!")
	end)
end)
