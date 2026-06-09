package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

local nj = require("ninjection")

describe("ninjection literal placeholder round-trip #e2e #bash-nix #literal", function()
	it("de-escapes a Nix literal ''${var} to ${var} in the child buffer", function()
		vim.cmd("edit tests/ft/nix/bash/bash_literal.nix")
		vim.api.nvim_win_set_cursor(0, { 5, 11 }) -- inside the injected bash block

		nj.edit()
		local child_buf = vim.api.nvim_get_current_buf()
		local child_text = table.concat(vim.api.nvim_buf_get_lines(child_buf, 0, -1, false), "\n")

		assert.is_truthy(child_text:find("${HOME}", 1, true), "child should contain de-escaped ${HOME}")
		assert.is_nil(child_text:find("''" .. "${HOME}", 1, true), "child should NOT contain the literal escape ''${HOME}")

		vim.cmd("bdelete!")
	end)

	it("round-trips an unedited literal back to the parent unchanged", function()
		vim.cmd("edit tests/ft/nix/bash/bash_literal.nix")
		local parent_buf = vim.api.nvim_get_current_buf()
		local before = vim.api.nvim_buf_get_lines(parent_buf, 0, -1, false)

		vim.api.nvim_win_set_cursor(0, { 5, 11 })
		nj.edit()
		nj.replace()

		local after = vim.api.nvim_buf_get_lines(parent_buf, 0, -1, false)
		assert.are.same(before, after)

		vim.cmd("bdelete!")
	end)

	it("escapes a freshly-typed ${VAR} on write-back, alongside the original", function()
		vim.cmd("edit tests/ft/nix/bash/bash_literal.nix")
		local parent_buf = vim.api.nvim_get_current_buf()

		vim.api.nvim_win_set_cursor(0, { 5, 11 })
		nj.edit()
		local child_buf = vim.api.nvim_get_current_buf()

		-- child shows the de-escaped original; add a freshly-typed expansion
		vim.api.nvim_buf_set_lines(child_buf, 0, -1, false, { "echo ${HOME}", "echo ${USER}" })

		nj.replace()

		local after = vim.api.nvim_buf_get_lines(parent_buf, 0, -1, false)
		local expected = {
			"{ pkgs }:",
			"{",
			"  script = # bash",
			"    ''",
			"      echo ''" .. "${HOME}",
			"      echo ''" .. "${USER}",
			"    '';",
			"}",
		}
		assert.are.same(expected, after)

		vim.cmd("bdelete!")
	end)
end)
