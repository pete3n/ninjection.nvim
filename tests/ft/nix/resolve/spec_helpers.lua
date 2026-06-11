--- Shared helpers for the resolve specs. Not a `_spec` file, so Plenary's
--- directory runner skips it; specs load it with
--- `dofile("tests/ft/nix/resolve/spec_helpers.lua")` (Plenary children run
--- from the repo root).

local M = {}

--- Whether the nix toolchain and the given flake root's pinned nixpkgs source
--- are reachable offline. When false, the eval-dependent specs skip (the
--- offline-CI source seeding is a separately-scoped follow-up per ADR-0006).
---@param root string The flake root whose nixpkgs input is probed.
---@return boolean
function M.nix_source_available(root)
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

--- virt_text chunks of every resolve extmark in the buffer, flattened to strings.
---@param bufnr integer
---@return string[]
function M.resolve_virt_texts(bufnr)
	local namespace = vim.api.nvim_create_namespace("ninjection_resolve")
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })
	local texts = {}
	for _, mark in ipairs(marks) do
		local chunks = mark[4] and mark[4].virt_text or {}
		local parts = {}
		for _, chunk in ipairs(chunks) do
			parts[#parts + 1] = chunk[1]
		end
		texts[#texts + 1] = table.concat(parts)
	end
	return texts
end

return M
