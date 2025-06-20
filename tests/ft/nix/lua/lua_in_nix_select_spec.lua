package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

local eq = assert.are.same
local nj = require("ninjection")

describe("ninjection.select integration test #e2e #lua-nix #select", function()
	it("validates injected content in select buffer", function()
		vim.cmd("edit /ninjection/tests/ft/nix/lua/lua_select.nix")

		local p_content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		if _G.test_debug then
			print("Buffer content before select:\n" .. table.concat(p_content, "\n"))
		end

		vim.api.nvim_win_set_cursor(0, { 5, 7 })
		nj.select()

		vim.cmd('normal! "zy')
		local copied = vim.fn.getreg("z", 1)

		if type(copied) == "string" then
			copied = vim.split(copied, "\n", { plain = true })
		end

		-- Remove trailing empty line if present
		if copied[#copied] == "" then
			table.remove(copied)
		end

		local expected = {
			"    ''",
			"      local lua_content",
			"      local more_lua_content",
			"      for i = 1, 10, 1 do",
			"        lua_content = lua_content + 1",
			"      end",
			"    '';",
		}

		if _G.test_debug then
			print("Selected visual text:\n" .. table.concat(copied, "\n"))
		end

		eq(expected, copied)
		vim.cmd("bdelete!")
	end)
end)
