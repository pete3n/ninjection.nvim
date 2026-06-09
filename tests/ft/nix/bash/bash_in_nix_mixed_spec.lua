package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

local nj = require("ninjection")

describe("ninjection mixed literal + interpreted round-trip #e2e #bash-nix #mixed", function()
	it("declares both a bare literal and an arrowed interpreted var in the block", function()
		vim.cmd("edit tests/ft/nix/bash/bash_mixed.nix")
		vim.api.nvim_win_set_cursor(0, { 5, 10 })

		nj.edit()
		local child_buf = vim.api.nvim_get_current_buf()
		local head = vim.api.nvim_buf_get_lines(child_buf, 0, 5, false)

		assert.are.same({
			"#!/usr/bin/env bash",
			"# >>> ninjection:nix",
			'pkgs_0x2E_hello="" # <- pkgs.hello',
			'HOME=""',
			"# <<< ninjection",
		}, head)

		vim.cmd("bdelete!")
	end)

	it("round-trips a literal and an interpolation together, unchanged", function()
		vim.cmd("edit tests/ft/nix/bash/bash_mixed.nix")
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
