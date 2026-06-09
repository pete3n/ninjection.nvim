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
-- ADR-0001; declarative descriptor table for now. Currently only the shebang;
-- the fenced ninjection block of declarations lands in a later slice.

---@type table<string, { shebang: string }>
local HEADERS = {
	bash = { shebang = "#!/usr/bin/env bash" },
	sh = { shebang = "#!/usr/bin/env sh" },
}

---@brief
--- Render the language-header lines for an injected language. Returns an empty
--- list for languages without a descriptor (the round-trip is then header-less).
---@param inj_lang string The injected (child) language.
---@return string[] header The header lines, top to bottom.
function M.render_header(inj_lang)
	local desc = HEADERS[inj_lang]
	if not desc then
		return {}
	end
	return { desc.shebang }
end

---@brief
--- Strip a previously-rendered language header from child lines on write-back.
--- Only removes the leading lines if they still match the rendered header, so a
--- buffer whose header was altered or removed is written back unchanged rather
--- than corrupted.
---@param lines string[] The child lines.
---@param inj_lang string The injected (child) language.
---@return string[] lines The lines with the matching header removed.
function M.strip_header(lines, inj_lang)
	local header = M.render_header(inj_lang)
	if #header == 0 then
		return lines
	end

	for i, h in ipairs(header) do
		if lines[i] ~= h then
			return lines
		end
	end

	return vim.list_slice(lines, #header + 1)
end

return M
