local nj = require("ninjection")

--- virt_text chunks of every resolve extmark in the buffer, flattened to strings.
local function resolve_virt_texts(bufnr)
	local ns = vim.api.nvim_create_namespace("ninjection_resolve")
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
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

		local after = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		assert.are.same(before, after, "resolve must not mutate the buffer")

		local rendered = table.concat(resolve_virt_texts(bufnr), "\n")
		assert.is_truthy(rendered:match("/nix/store/.*hello"), "expected the store path in virtual text, got: " .. rendered)

		vim.cmd("bdelete!")
	end)

	it("reports a bound-by-caller interpolation without mutating the buffer", function()
		vim.cmd("edit tests/ft/nix/resolve/resolve_bound_by_caller.nix")
		local bufnr = vim.api.nvim_get_current_buf()
		local before = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		vim.api.nvim_win_set_cursor(0, { 5, 8 })

		local ok = nj.resolve()
		assert.is_true(ok, "resolve verb should succeed even when bound by caller")

		local after = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		assert.are.same(before, after, "resolve must not mutate the buffer")

		local rendered = table.concat(resolve_virt_texts(bufnr), "\n")
		assert.is_truthy(rendered:match("caller"), "expected a bound-by-caller note, got: " .. rendered)

		vim.cmd("bdelete!")
	end)
end)
