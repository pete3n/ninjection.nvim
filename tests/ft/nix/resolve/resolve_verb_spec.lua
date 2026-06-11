local nj = require("ninjection")
local helpers = dofile("tests/ft/nix/resolve/spec_helpers.lua")
local nix_source_available = helpers.nix_source_available
local resolve_virt_texts = helpers.resolve_virt_texts

describe("ninjection.resolve() verb #e2e #nix #resolve", function()
	it("renders the resolved store path as non-destructive virtual text", function()
		if not nix_source_available(vim.fn.getcwd()) then
			pending("nix / pinned nixpkgs source unavailable")
			return
		end

		vim.cmd("edit tests/ft/nix/resolve/resolve_unbound.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		local before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		vim.api.nvim_win_set_cursor(0, { 4, 8 })

		local ok, err = nj.resolve()
		assert.is_true(ok, "resolve verb should succeed: " .. tostring(err))

		-- The eval is asynchronous; the rendering arrives via the event loop.
		local rendered = ""
		vim.wait(30000, function()
			rendered = table.concat(resolve_virt_texts(bufnr), "\n")
			return rendered:match("/nix/store/.*hello") ~= nil
		end, 50)
		assert.is_truthy(rendered:match("/nix/store/.*hello"), "expected the store path in virtual text, got: " .. rendered)

		local after = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		assert.are.same(before, after, "resolve must not mutate the buffer")

		vim.cmd("bdelete!")
	end)

	it("reports a bound-by-caller interpolation without mutating the buffer", function()
		vim.cmd("edit tests/ft/nix/resolve/resolve_bound_by_caller.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		local before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		vim.api.nvim_win_set_cursor(0, { 5, 8 })

		local ok = nj.resolve()
		assert.is_true(ok, "resolve verb should succeed even when bound by caller")

		-- Even a no-eval condition is delivered via the event loop, never synchronously.
		local rendered = ""
		vim.wait(10000, function()
			rendered = table.concat(resolve_virt_texts(bufnr), "\n")
			return rendered:match("caller") ~= nil
		end, 50)
		assert.is_truthy(rendered:match("caller"), "expected a bound-by-caller note, got: " .. rendered)

		local after = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		assert.are.same(before, after, "resolve must not mutate the buffer")

		vim.cmd("bdelete!")
	end)
end)
