local resolve = require("ninjection.resolve")

describe("ninjection.resolve async engine #e2e #nix #resolve", function()
	it("delivers a let-bound value to the callback without blocking the caller", function()
		if vim.fn.executable("nix") == 0 then
			pending("nix unavailable")
			return
		end
		local root = vim.fn.getcwd()

		vim.cmd("edit tests/ft/nix/resolve/resolve_let.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- Cursor inside ${greeting} on the injected content line.
		vim.api.nvim_win_set_cursor(0, { 7, 8 })

		local node, find_err = resolve.find_interpolation(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find an interpolation node at the cursor: " .. tostring(find_err))

		---@type boolean, NJResolution?, string?
		local delivered, got_result, got_err = false, nil, nil
		resolve.resolve(node, bufnr, root, function(result, err)
			delivered, got_result, got_err = true, result, err
		end)
		assert.is_false(delivered, "the result must be delivered via the event loop, never synchronously")

		vim.wait(10000, function()
			return delivered
		end, 50)
		assert.is_true(delivered, "the callback should have been invoked")
		assert.is_truthy(got_result, "expected a result, got error: " .. tostring(got_err))
		assert.are.equal("hi from let", got_result and got_result.path)

		vim.cmd("bdelete!")
	end)

	it("delivers bound_by_caller via the event loop without spawning an eval", function()
		local root = vim.fn.getcwd()

		vim.cmd("edit tests/ft/nix/resolve/resolve_bound_by_caller.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- ${pkgs.hello} sits one line lower than the unbound fixture (formals header).
		vim.api.nvim_win_set_cursor(0, { 5, 8 })

		local node = resolve.find_interpolation(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find an interpolation node at the cursor")

		---@type boolean, NJResolution?, string?
		local delivered, got_result, got_err = false, nil, nil
		resolve.resolve(node, bufnr, root, function(result, err)
			delivered, got_result, got_err = true, result, err
		end)
		assert.is_false(delivered, "even a no-eval condition must not be delivered synchronously")

		-- No eval is spawned, so delivery needs only the scheduler — no nix, no flake.
		vim.wait(1000, function()
			return delivered
		end, 10)
		assert.is_true(delivered, "the callback should have been invoked")
		assert.is_truthy(got_result, "expected a result, got error: " .. tostring(got_err))
		assert.are.equal("pkgs", got_result and got_result.bound_by_caller)
		assert.is_nil(got_result and got_result.path, "a caller-bound interpolation has no resolved value")

		vim.cmd("bdelete!")
	end)

	it("delivers nil and an error to the callback when the eval fails", function()
		if vim.fn.executable("nix") == 0 then
			pending("nix unavailable")
			return
		end

		vim.cmd("edit tests/ft/nix/resolve/resolve_unbound.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		vim.api.nvim_win_set_cursor(0, { 4, 8 })

		local node = resolve.find_interpolation(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find an interpolation node at the cursor")

		-- A root that is not a flake makes the synthesized getFlake preamble fail.
		---@type boolean, NJResolution?, string?
		local delivered, got_result, got_err = false, nil, nil
		resolve.resolve(node, bufnr, "/nonexistent-flake-root", function(result, err)
			delivered, got_result, got_err = true, result, err
		end)

		vim.wait(10000, function()
			return delivered
		end, 50)
		assert.is_true(delivered, "the callback should have been invoked")
		assert.is_nil(got_result, "a failed eval must not deliver a result")
		assert.is_truthy(got_err and got_err:match("nix eval failed"), "expected an eval error, got: " .. tostring(got_err))

		vim.cmd("bdelete!")
	end)
end)
