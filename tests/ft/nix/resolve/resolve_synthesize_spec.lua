local resolve = require("ninjection.resolve")

--- Whether the nix toolchain and the pinned nixpkgs source are reachable offline.
--- When false, the eval-dependent spec skips (the offline-CI source seeding is a
--- separately-scoped follow-up per ADR-0006).
local function nix_source_available(root)
	if vim.fn.executable("nix") == 0 then
		return false
	end
	local expr = 'builtins.toString ((builtins.getFlake "'
		.. root
		.. '").inputs.nixpkgs.legacyPackages.${builtins.currentSystem}.hello)'
	local out = vim
		.system({
			"nix",
			"eval",
			"--offline",
			"--impure",
			"--extra-experimental-features",
			"nix-command flakes",
			"--raw",
			"--expr",
			expr,
		}, { text = true })
		:wait()
	return out.code == 0 and out.stdout:match("^/nix/store/") ~= nil
end

describe("ninjection.resolve synthesis #e2e #nix #resolve", function()
	it("supplies pkgs from the pinned flake root for an unbound interpolation", function()
		local root = vim.fn.getcwd()

		vim.cmd("edit tests/ft/nix/resolve/resolve_unbound.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- Cursor inside ${pkgs.hello} on the injected content line.
		vim.api.nvim_win_set_cursor(0, { 4, 8 })

		local node, find_err = resolve.find_interpolation(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find an interpolation node at the cursor: " .. tostring(find_err))

		local result, syn_err = resolve.synthesize(node, bufnr, root)
		assert.is_truthy(result, "synthesize should return a result: " .. tostring(syn_err))
		assert.are.equal(
			'let pkgs = (builtins.getFlake "'
				.. root
				.. '").inputs.nixpkgs.legacyPackages.${builtins.currentSystem}; in builtins.toString (pkgs.hello)',
			result.expr
		)

		vim.cmd("bdelete!")
	end)

	it("reports bound_by_caller when the head name is a function formal", function()
		local root = vim.fn.getcwd()

		vim.cmd("edit tests/ft/nix/resolve/resolve_bound_by_caller.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- ${pkgs.hello} sits one line lower than the unbound fixture (formals header).
		vim.api.nvim_win_set_cursor(0, { 5, 8 })

		local node = resolve.find_interpolation(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find an interpolation node at the cursor")

		local result, syn_err = resolve.synthesize(node, bufnr, root)
		assert.is_truthy(result, "synthesize should return a result: " .. tostring(syn_err))
		assert.are.equal("pkgs", result.bound_by_caller)
		assert.is_nil(result.expr, "a caller-bound interpolation has no synthesized expression")

		vim.cmd("bdelete!")
	end)

	it("reconstructs the in-file let binding for a self-contained interpolation", function()
		local root = vim.fn.getcwd()

		vim.cmd("edit tests/ft/nix/resolve/resolve_let.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- Cursor inside ${greeting} on the injected content line.
		vim.api.nvim_win_set_cursor(0, { 7, 8 })

		local node = resolve.find_interpolation(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find an interpolation node at the cursor")

		local result, syn_err = resolve.synthesize(node, bufnr, root)
		assert.is_truthy(result, "synthesize should return a result: " .. tostring(syn_err))
		assert.are.equal('let greeting = "hi from let"; in builtins.toString (greeting)', result.expr)

		-- The reconstructed expression is self-contained (no flake/nixpkgs needed),
		-- so it resolves offline wherever `nix` exists.
		if vim.fn.executable("nix") == 1 then
			---@type NJResolution?
			local resolved
			resolve.resolve(node, bufnr, root, function(callback_result)
				resolved = callback_result
			end)
			vim.wait(10000, function()
				return resolved ~= nil
			end, 50)
			assert.are.equal("hi from let", resolved and resolved.path)
		end

		vim.cmd("bdelete!")
	end)

	it("resolves an unbound interpolation to its real store path", function()
		local root = vim.fn.getcwd()
		if not nix_source_available(root) then
			pending("nix / pinned nixpkgs source unavailable")
			return
		end

		vim.cmd("edit tests/ft/nix/resolve/resolve_unbound.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		vim.api.nvim_win_set_cursor(0, { 4, 8 })

		local node = resolve.find_interpolation(bufnr, vim.api.nvim_win_get_cursor(0))
		---@type NJResolution?, string?
		local result, err
		---@type boolean
		local delivered = false
		resolve.resolve(node, bufnr, root, function(callback_result, callback_err)
			delivered, result, err = true, callback_result, callback_err
		end)
		vim.wait(30000, function()
			return delivered
		end, 50)
		assert.is_truthy(result, "resolve should deliver a result: " .. tostring(err))
		assert.is_truthy(
			result and result.path and result.path:match("^/nix/store/.*hello"),
			"expected a hello store path, got: " .. tostring(result and result.path)
		)

		vim.cmd("bdelete!")
	end)
end)
