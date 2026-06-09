---@module "ninjection.placeholder"
---@brief
--- Treesitter-driven round-trip of host interpolations to editable placeholders
--- in the injected language. See docs/adr/0001 (split parent transform from
--- header render) and docs/adr/0002 (Treesitter is the sole structural parser).
---
--- This module currently implements only the literal-placeholder path for a Nix
--- host: a Nix indented string escapes a literal `${x}` as `''${x}`, which the
--- grammar represents as a `dollar_escape` node (the `''`) immediately followed
--- by the plain `$` and `{x}` text. De-escaping for editing simply drops the
--- `dollar_escape` nodes; the injected language then sees a valid `${x}`.

local M = {}

--- Host (parent) language whose literal-escape semantics this module knows.
--- Escaping is parent-keyed (ADR-0001); for any other host the round-trip is a
--- no-op for now, until a second host language warrants a descriptor table.
local HOST = "nix"

--- Host node type whose text is the literal-escape marker to drop on the way in.
local NIX_LITERAL_ESCAPE = "dollar_escape"

---@brief
--- De-escape host literal escapes in an injection so the injected language sees
--- valid syntax. Treesitter identifies the escape nodes; we reconstruct the
--- injection text from the node's children, dropping the escapes. Interpolations
--- and all other content are preserved verbatim.
---
---@param node TSNode The injected content node, in the host (parent) language.
---@param bufnr integer The parent buffer the node lives in.
---@param host_ft string The host (parent) filetype.
---@return string text The injection text with literal escapes removed.
function M.forward(node, bufnr, host_ft)
	if host_ft ~= HOST then
		return vim.treesitter.get_node_text(node, bufnr)
	end

	---@type string[]
	local parts = {}
	for child in node:iter_children() do
		if child:type() ~= NIX_LITERAL_ESCAPE then
			parts[#parts + 1] = vim.treesitter.get_node_text(child, bufnr)
		end
	end
	return table.concat(parts)
end

--- Injected-language Treesitter node type for a braced `${...}` expansion. Only
--- braced expansions interpolate in a Nix host, so a bare `$VAR`
--- (`simple_expansion`) needs no escaping.
local INJECTED_EXPANSION = "expansion"

---@brief
--- Re-escape injected-language `${x}` expansions back into host literal escapes
--- (`''${x}`) for write-back. Treesitter finds the expansions in the child buffer
--- (ADR-0002); we prepend the host escape onto each TS-identified slice. If the
--- injected language has no grammar, the lines are returned unchanged.
---
---@param bufnr integer The child buffer, in the injected language.
---@param host_ft string The host (parent) filetype to restore escaping for.
---@return string[] lines The child lines with `${x}` re-escaped to `''${x}`.
function M.reverse(bufnr, host_ft)
	---@type string[]
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	if host_ft ~= HOST then
		return lines
	end

	---@type boolean, vim.treesitter.LanguageTree?
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not ok or not parser then
		return lines
	end
	---@cast parser vim.treesitter.LanguageTree

	-- The injected language may have no `${...}` expansion concept (e.g. Lua), in
	-- which case the query is invalid for its grammar; treat that as nothing to
	-- re-escape rather than an error.
	local q_ok, query = pcall(vim.treesitter.query.parse, parser:lang(), "(" .. INJECTED_EXPANSION .. ") @e")
	if not q_ok or not query then
		return lines
	end

	local root = parser:parse()[1]:root()

	---@type integer[][]
	local positions = {}
	for _, node in query:iter_captures(root, bufnr, 0, -1) do
		local s_row, s_col = node:range()
		positions[#positions + 1] = { s_row, s_col }
	end

	-- Insert from last to first so earlier edits don't shift later coordinates.
	table.sort(positions, function(a, b)
		if a[1] ~= b[1] then
			return a[1] > b[1]
		end
		return a[2] > b[2]
	end)

	for _, p in ipairs(positions) do
		local row, col = p[1], p[2]
		local line = lines[row + 1]
		lines[row + 1] = line:sub(1, col) .. "''" .. line:sub(col + 1)
	end

	return lines
end

-- Language header (injected-keyed) ----------------------------------------
-- The header is ephemeral scaffolding prepended to the child buffer for the
-- injected language's tooling and stripped on write-back. Injected-keyed per
-- ADR-0001; declarative descriptor table for now. It carries the shebang Nix
-- synthesises at build time plus a fenced "ninjection block" of real variable
-- declarations so the injected LSP does not flag the placeholder references.

---@type table<string, { shebang: string, comment: string, assign: string, default: string }>
local HEADERS = {
	bash = { shebang = "#!/usr/bin/env bash", comment = "#", assign = "=", default = '""' },
	sh = { shebang = "#!/usr/bin/env sh", comment = "#", assign = "=", default = '""' },
}

local FENCE_OPEN = " >>> ninjection:"
local FENCE_CLOSE = " <<< ninjection"

---@brief
--- Collect the placeholder variable names declared by `${name}` expansions in
--- the child buffer, in first-seen order without duplicates. Treesitter reads
--- the names (ADR-0002); a grammar without `${}` yields none.
---@param bufnr integer The child buffer, in the injected language.
---@return string[] names
function M.collect_placeholders(bufnr)
	---@type boolean, vim.treesitter.LanguageTree?
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not ok or not parser then
		return {}
	end
	---@cast parser vim.treesitter.LanguageTree

	local q_ok, query =
		pcall(vim.treesitter.query.parse, parser:lang(), "(" .. INJECTED_EXPANSION .. " (variable_name) @name)")
	if not q_ok or not query then
		return {}
	end

	local root = parser:parse()[1]:root()
	---@type table<string, boolean>
	local seen = {}
	---@type string[]
	local names = {}
	for _, node in query:iter_captures(root, bufnr, 0, -1) do
		local name = vim.treesitter.get_node_text(node, bufnr)
		if not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	return names
end

---@brief
--- Build the language-header lines: the shebang, then (when there are vars) a
--- fenced ninjection block declaring each at the injected language's default
--- value. Returns an empty list for languages without a descriptor.
---@param inj_lang string The injected (child) language.
---@param parent_lang string The host (parent) filetype, recorded in the fence.
---@param vars string[] Placeholder names to declare.
---@return string[] header
function M.build_header(inj_lang, parent_lang, vars)
	local desc = HEADERS[inj_lang]
	if not desc then
		return {}
	end

	---@type string[]
	local lines = { desc.shebang }
	if vars and #vars > 0 then
		lines[#lines + 1] = desc.comment .. FENCE_OPEN .. parent_lang
		for _, v in ipairs(vars) do
			lines[#lines + 1] = v .. desc.assign .. desc.default
		end
		lines[#lines + 1] = desc.comment .. FENCE_CLOSE
	end
	return lines
end

---@brief
--- Strip the language header from child lines on write-back. When a ninjection
--- block is present, removes everything through its closing fence (shebang and
--- block); otherwise removes a matching lone shebang. A buffer whose header was
--- altered or removed is returned unchanged rather than corrupted.
---@param lines string[] The child lines.
---@param inj_lang string The injected (child) language.
---@return string[] lines The lines with the header removed.
function M.strip_header(lines, inj_lang)
	local desc = HEADERS[inj_lang]
	if not desc then
		return lines
	end

	local close = desc.comment .. FENCE_CLOSE
	for i, line in ipairs(lines) do
		if line == close then
			return vim.list_slice(lines, i + 1)
		end
	end

	if lines[1] == desc.shebang then
		return vim.list_slice(lines, 2)
	end
	return lines
end

return M
