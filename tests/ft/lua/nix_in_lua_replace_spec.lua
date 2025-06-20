package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

local eq = assert.are.same
local nj = require("ninjection")

describe("ninjection.replace integration test #e2e #nix-lua #replace", function()
	it("partially replaces injected content in the parent buffer", function()
		vim.cmd("edit /ninjection/tests/ft/lua/nix_replace.lua")

		local parent_buf = vim.api.nvim_get_current_buf()
		local p_before = vim.api.nvim_buf_get_lines(parent_buf, 0, -1, false)
		if _G.test_debug then
			print("Buffer content before edit:\n" .. table.concat(p_before, "\n"))
		end

		vim.api.nvim_win_set_cursor(0, { 5, 7 }) -- Cursor inside injected block
		nj.edit()
		local child_buf = vim.api.nvim_get_current_buf()

		local partial = vim.api.nvim_buf_get_lines(child_buf, 0, -1, false)
		partial[2] = "# updated second line"

		vim.api.nvim_buf_set_lines(child_buf, 0, -1, false, partial)

		nj.replace()

		local p_after = vim.api.nvim_buf_get_lines(parent_buf, 0, -1, false)
		if _G.test_debug then
			print("Buffer content after replace:\n" .. table.concat(p_after, "\n"))
		end

		local expected = {
			"local injected_content_edit = -- nix",
			"  [[",
			"    let",
		  "    # updated second line",
			"    in",
			"    if builtins.isAttrs flake.outputs.devShells.x86_64-linux.default then",
			"      builtins.attrNames flake.outputs.devShells.x86_64-linux.default",
			"    else",
			'      "LEAF"',
			"  ]]",
			"print(injected_content_edit)",
		}

		eq(expected, p_after)

		vim.cmd("bdelete!")
	end)
end)
