package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

local nj = require("ninjection")

describe("ninjection interpreted placeholder round-trip #e2e #bash-nix #interp", function()
	it("renames a Nix interpolation ${pkgs.x} to a safe id in the child body", function()
		vim.cmd("edit tests/ft/nix/bash/bash_interp.nix")
		vim.api.nvim_win_set_cursor(0, { 5, 10 })

		nj.edit()
		local child_buf = vim.api.nvim_get_current_buf()
		local text = table.concat(vim.api.nvim_buf_get_lines(child_buf, 0, -1, false), "\n")

		assert.is_truthy(text:find("${pkgs_0x2Ehello}", 1, true), "child body should contain the renamed id")
		assert.is_nil(text:find("${pkgs.hello}", 1, true), "child should not contain the raw Nix interpolation")

		vim.cmd("bdelete!")
	end)

	it("declares an interpreted placeholder with a # <- host arrow in the block", function()
		vim.cmd("edit tests/ft/nix/bash/bash_interp.nix")
		vim.api.nvim_win_set_cursor(0, { 5, 10 })

		nj.edit()
		local child_buf = vim.api.nvim_get_current_buf()
		local head = vim.api.nvim_buf_get_lines(child_buf, 0, 4, false)

		assert.are.same({
			"#!/usr/bin/env bash",
			"# >>> ninjection:nix",
			'pkgs_0x2Ehello="" # <- pkgs.hello',
			"# <<< ninjection",
		}, head)

		vim.cmd("bdelete!")
	end)

	it("round-trips an unedited interpolation back to the parent unchanged", function()
		vim.cmd("edit tests/ft/nix/bash/bash_interp.nix")
		local parent_buf = vim.api.nvim_get_current_buf()
		local before = vim.api.nvim_buf_get_lines(parent_buf, 0, -1, false)

		vim.api.nvim_win_set_cursor(0, { 5, 10 })
		nj.edit()
		nj.replace()

		local after = vim.api.nvim_buf_get_lines(parent_buf, 0, -1, false)
		assert.are.same(before, after)

		vim.cmd("bdelete!")
	end)
end)
