package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

local nj = require("ninjection")

describe("ninjection positional parameters #e2e #bash-nix #positional", function()
	it("does not declare shell positional parameters in the block", function()
		vim.cmd("edit tests/ft/nix/bash/bash_positional.nix")
		vim.api.nvim_win_set_cursor(0, { 5, 11 })

		nj.edit()
		local child_buf = vim.api.nvim_get_current_buf()
		local head = vim.api.nvim_buf_get_lines(child_buf, 0, 4, false)

		-- Only HOME is declared; ${1} is a positional parameter, not a declarable var.
		assert.are.same({
			"#!/usr/bin/env bash",
			"# >>> ninjection:nix",
			'HOME=""',
			"# <<< ninjection",
		}, head)

		vim.cmd("bdelete!")
	end)

	it("still round-trips a positional ''${1} unchanged", function()
		vim.cmd("edit tests/ft/nix/bash/bash_positional.nix")
		local parent_buf = vim.api.nvim_get_current_buf()
		local before = vim.api.nvim_buf_get_lines(parent_buf, 0, -1, false)

		vim.api.nvim_win_set_cursor(0, { 5, 11 })
		nj.edit()
		nj.replace()

		local after = vim.api.nvim_buf_get_lines(parent_buf, 0, -1, false)
		assert.are.same(before, after)

		vim.cmd("bdelete!")
	end)
end)
