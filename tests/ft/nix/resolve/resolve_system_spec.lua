local nj = require("ninjection")
local resolve = require("ninjection.resolve")
local helpers = dofile("tests/ft/nix/resolve/spec_helpers.lua")
local nix_source_available = helpers.nix_source_available
local resolve_virt_texts = helpers.resolve_virt_texts

--- The NixOS-system fixture flake: flake.nix instantiates configuration.nix as
--- a module of `nixpkgs.lib.nixosSystem`, the common real-world shape where
--- `pkgs` reaches the module from the flake's pinned nixpkgs input.
local FIXTURE_ROOT_REL = "tests/ft/nix/resolve/caller_flake/system"

describe("ninjection.resolve NixOS system flake #e2e #nix #resolve", function()
	it("finds a bare variable as the resolvable node when no interpolation encloses the cursor", function()
		vim.cmd("edit " .. FIXTURE_ROOT_REL .. "/configuration.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- Cursor on `wget` inside `environment.systemPackages = with pkgs; [ ... ]`.
		vim.api.nvim_win_set_cursor(0, { 56, 4 })

		local node, find_err = resolve.find_resolvable(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find a resolvable node at the cursor: " .. tostring(find_err))
		assert.are.equal("wget", vim.treesitter.get_node_text(node, bufnr))

		vim.cmd("bdelete!")
	end)

	it("reconstructs pkgs for a module formal from the nixosSystem call site", function()
		local root = vim.fn.getcwd() .. "/" .. FIXTURE_ROOT_REL

		vim.cmd("edit " .. FIXTURE_ROOT_REL .. "/configuration.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- Cursor on `wget` inside `environment.systemPackages = with pkgs; [ ... ]`.
		vim.api.nvim_win_set_cursor(0, { 56, 4 })

		local node, find_err = resolve.find_resolvable(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find a resolvable node at the cursor: " .. tostring(find_err))

		-- The with environment's head (`pkgs`) is a formal of the module function,
		-- but the caller is in view: flake.nix lists ./configuration.nix among the
		-- modules of `nixpkgs.lib.nixosSystem`, which binds `pkgs` from the pinned
		-- nixpkgs input for the system declared at the call site.
		local result, syn_err = resolve.synthesize(node, bufnr, root)
		assert.is_truthy(result, "synthesize should return a result: " .. tostring(syn_err))
		assert.is_nil(result.bound_by_caller, "a formal bound at the nixosSystem call site is resolvable")
		assert.are.equal(
			'let nixpkgs = (builtins.getFlake "'
				.. root
				.. '").inputs.nixpkgs; in let pkgs = nixpkgs.legacyPackages.${"x86_64-linux"}; in with pkgs; builtins.toString (wget)',
			result.expr
		)

		vim.cmd("bdelete!")
	end)

	it("synthesizes each list member independently (curl alongside wget)", function()
		local root = vim.fn.getcwd() .. "/" .. FIXTURE_ROOT_REL

		vim.cmd("edit " .. FIXTURE_ROOT_REL .. "/configuration.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- Cursor on `curl`, the next member of the same systemPackages list.
		vim.api.nvim_win_set_cursor(0, { 57, 4 })

		local node, find_err = resolve.find_resolvable(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find a resolvable node at the cursor: " .. tostring(find_err))
		assert.are.equal("curl", vim.treesitter.get_node_text(node, bufnr))

		local result, syn_err = resolve.synthesize(node, bufnr, root)
		assert.is_truthy(result, "synthesize should return a result: " .. tostring(syn_err))
		assert.are.equal(
			'let nixpkgs = (builtins.getFlake "'
				.. root
				.. '").inputs.nixpkgs; in let pkgs = nixpkgs.legacyPackages.${"x86_64-linux"}; in with pkgs; builtins.toString (curl)',
			result.expr
		)

		vim.cmd("bdelete!")
	end)

	it("reports bound_by_caller for a with environment whose module is never instantiated", function()
		local root = vim.fn.getcwd() .. "/" .. FIXTURE_ROOT_REL

		vim.cmd("edit " .. FIXTURE_ROOT_REL .. "/orphan.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- Cursor on `wget` inside `with pkgs; [ ... ]`.
		vim.api.nvim_win_set_cursor(0, { 6, 4 })

		local node, find_err = resolve.find_resolvable(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find a resolvable node at the cursor: " .. tostring(find_err))

		-- flake.nix is in view but no modules list names ./orphan.nix, so the
		-- with environment's formal cannot be reconstructed.
		local result, syn_err = resolve.synthesize(node, bufnr, root)
		assert.is_truthy(result, "synthesize should return a result: " .. tostring(syn_err))
		assert.are.equal("pkgs", result.bound_by_caller)
		assert.is_nil(result.expr, "a caller-bound with environment has no synthesized expression")

		vim.cmd("bdelete!")
	end)

	it("resolves a systemPackages member to its real store path", function()
		local root = vim.fn.getcwd() .. "/" .. FIXTURE_ROOT_REL
		if not nix_source_available(root) then
			pending("nix / pinned nixpkgs source unavailable")
			return
		end

		vim.cmd("edit " .. FIXTURE_ROOT_REL .. "/configuration.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- Cursor on `wget` inside `environment.systemPackages = with pkgs; [ ... ]`.
		vim.api.nvim_win_set_cursor(0, { 56, 4 })

		local node = resolve.find_resolvable(bufnr, vim.api.nvim_win_get_cursor(0))
		assert.is_truthy(node, "should find a resolvable node at the cursor")

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
			result and result.path and result.path:match("^/nix/store/.*wget"),
			"expected a wget store path, got: " .. tostring(result and result.path)
		)

		vim.cmd("bdelete!")
	end)

	it("the resolve verb accepts a bare variable, not only an interpolation", function()
		vim.cmd("edit " .. FIXTURE_ROOT_REL .. "/orphan.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		-- Cursor on `wget` inside `with pkgs; [ ... ]` — no `${...}` anywhere.
		vim.api.nvim_win_set_cursor(0, { 6, 4 })

		local ok, err = nj.resolve()
		assert.is_true(ok, "resolve verb should accept a bare variable: " .. tostring(err))

		-- Whatever root wins (workspace folder or cwd), orphan.nix is never
		-- instantiated, so the rendered outcome is the bound-by-caller note.
		local rendered = ""
		vim.wait(10000, function()
			rendered = table.concat(resolve_virt_texts(bufnr), "\n")
			return rendered:match("caller") ~= nil
		end, 50)
		assert.is_truthy(rendered:match("bound by caller: pkgs"), "expected a bound-by-caller note, got: " .. rendered)

		vim.cmd("bdelete!")
	end)
end)
