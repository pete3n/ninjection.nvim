local resolve = require("ninjection.resolve")

--- The fixture flake whose flake.nix instantiates config.nix with `pkgs` bound
--- from the pinned nixpkgs input — the "knowing how the file is instantiated"
--- case ADR-0006 deferred.
local FIXTURE_ROOT_REL = "tests/ft/nix/resolve/caller_flake"

--- Whether the nix toolchain and the fixture flake's pinned nixpkgs source are
--- reachable offline. When false, the eval-dependent specs skip (the offline-CI
--- source seeding is a separately-scoped follow-up per ADR-0006).
---@param root string The fixture flake root.
---@return boolean
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

describe("ninjection.resolve caller reconstruction #e2e #nix #resolve", function()
	it("reconstructs an inherit-passed formal from the flake call site", function()
		local root = vim.fn.getcwd() .. "/" .. FIXTURE_ROOT_REL

		vim.cmd("edit " .. FIXTURE_ROOT_REL .. "/config.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- Cursor inside ${pkgs.hello} on the injected content line.
		vim.api.nvim_win_set_cursor(0, { 5, 8 })

		local node, find_err = resolve.find_interpolation(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find an interpolation node at the cursor: " .. tostring(find_err))

		-- The formal `pkgs` is bound by the caller, but the caller is in view:
		-- flake.nix imports config.nix with `inherit pkgs;`, `pkgs` is let-bound
		-- from the `nixpkgs` input, and a flake input *is* addressable — so the
		-- chain closes instead of reporting bound_by_caller.
		local result, syn_err = resolve.synthesize(node, bufnr, root)
		assert.is_truthy(result, "synthesize should return a result: " .. tostring(syn_err))
		assert.is_nil(result.bound_by_caller, "a caller bound at the flake call site is resolvable")
		assert.are.equal(
			'let nixpkgs = (builtins.getFlake "'
				.. root
				.. '").inputs.nixpkgs; in let pkgs = nixpkgs.legacyPackages.${builtins.currentSystem}; in builtins.toString (pkgs.hello)',
			result.expr
		)

		vim.cmd("bdelete!")
	end)

	it("reconstructs an explicit attr argument through the caller's scope", function()
		local root = vim.fn.getcwd() .. "/" .. FIXTURE_ROOT_REL

		vim.cmd("edit " .. FIXTURE_ROOT_REL .. "/config.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- Cursor inside ${lib.version} on the echo line.
		vim.api.nvim_win_set_cursor(0, { 6, 30 })

		local node, find_err = resolve.find_interpolation(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find an interpolation node at the cursor: " .. tostring(find_err))

		-- `lib` is not inherited but bound at the call site (`lib = pkgs.lib;`):
		-- the binding is spliced verbatim as the innermost clause and its head
		-- (`pkgs`) traced through the caller's scope to the nixpkgs input.
		local result, syn_err = resolve.synthesize(node, bufnr, root)
		assert.is_truthy(result, "synthesize should return a result: " .. tostring(syn_err))
		assert.are.equal(
			'let nixpkgs = (builtins.getFlake "'
				.. root
				.. '").inputs.nixpkgs; in let pkgs = nixpkgs.legacyPackages.${builtins.currentSystem}; in let lib = pkgs.lib; in builtins.toString (lib.version)',
			result.expr
		)

		-- The fixture pins nixos-26.05, so the resolved lib.version is pin-derived.
		if nix_source_available(root) then
			---@type NJResolution?
			local resolved
			resolve.resolve(node, bufnr, root, function(callback_result)
				resolved = callback_result
			end)
			vim.wait(30000, function()
				return resolved ~= nil
			end, 50)
			assert.is_truthy(
				resolved and resolved.path and resolved.path:match("^26%.05%."),
				"expected a nixos-26.05 lib.version, got: " .. tostring(resolved and resolved.path)
			)
		end

		vim.cmd("bdelete!")
	end)

	it("reports bound_by_caller for a file the flake never instantiates", function()
		local root = vim.fn.getcwd() .. "/" .. FIXTURE_ROOT_REL

		vim.cmd("edit " .. FIXTURE_ROOT_REL .. "/orphan.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- Cursor inside ${pkgs.hello} on the injected content line.
		vim.api.nvim_win_set_cursor(0, { 5, 8 })

		local node = resolve.find_interpolation(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find an interpolation node at the cursor")

		-- flake.nix is in view but has no `import ./orphan.nix` call site, so
		-- the formal's value genuinely lives in an unseen caller.
		local result, syn_err = resolve.synthesize(node, bufnr, root)
		assert.is_truthy(result, "synthesize should return a result: " .. tostring(syn_err))
		assert.are.equal("pkgs", result.bound_by_caller)
		assert.is_nil(result.expr, "a caller-bound interpolation has no synthesized expression")

		vim.cmd("bdelete!")
	end)

	it("resolves a caller-bound interpolation to its real store path", function()
		local root = vim.fn.getcwd() .. "/" .. FIXTURE_ROOT_REL
		if not nix_source_available(root) then
			pending("nix / pinned nixpkgs source unavailable")
			return
		end

		vim.cmd("edit " .. FIXTURE_ROOT_REL .. "/config.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- Cursor inside ${pkgs.hello} on the injected content line.
		vim.api.nvim_win_set_cursor(0, { 5, 8 })

		local node = resolve.find_interpolation(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find an interpolation node at the cursor")

		---@type boolean, NJResolution?, string?
		local delivered, result, err = false, nil, nil
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
