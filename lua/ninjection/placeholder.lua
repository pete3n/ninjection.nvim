---@module "ninjection.placeholder"
---@brief
--- Treesitter-driven round-trip of parent interpolations to editable placeholders
--- in the injected language. See docs/adr/0001 (split parent transform from
--- header render) and docs/adr/0002 (Treesitter is the sole structural parser).
---
--- This module currently implements only the literal-placeholder path for a Nix
--- parent: a Nix indented string escapes a literal `${x}` as `''${x}`, which the
--- grammar represents as a `dollar_escape` node (the `''`) immediately followed
--- by the plain `$` and `{x}` text. De-escaping for editing simply drops the
--- `dollar_escape` nodes; the injected language then sees a valid `${x}`.

local M = {}

--- Parent language whose literal-escape semantics this module knows. Escaping is
--- parent-keyed (ADR-0001); for any other parent the round-trip is a no-op for
--- now, until a second parent language warrants a descriptor table.
local PARENT_LANG = "nix"

--- Parent node type whose text is the literal-escape marker to drop on the way in.
local NIX_LITERAL_ESCAPE = "dollar_escape"

--- Parent node type for an evaluated `${expr}` interpolation, to be renamed.
local NIX_INTERPOLATION = "interpolation"

--- Injected-language header descriptors (injected-keyed, declarative; ADR-0001).
--- Each carries the shebang plus the comment syntax, assignment operator, and
--- default value used to render the ninjection block of declarations.
---@type table<string, { shebang: string, comment: string, assign: string, default: string }>
local HEADERS = {
	bash = { shebang = "#!/usr/bin/env bash", comment = "#", assign = "=", default = '""' },
	sh = { shebang = "#!/usr/bin/env sh", comment = "#", assign = "=", default = '""' },
}

--- Fixed markers for the fenced ninjection block.
local FENCE_OPEN = " >>> ninjection:"
local FENCE_CLOSE = " <<< ninjection"
local FENCE_ARROW = " <- "

---@brief
--- Rewrite a parent variable name into an injected-language-safe identifier by
--- replacing each character invalid in an identifier with `_0x<HEX>_` in place
--- (ADR-0003's rename encoding: stateless, self-documenting, position-preserving).
--- The trailing underscore keeps the marker legible when a name character follows
--- (e.g. `pkgs.Extra` -> `pkgs_0x2E_Extra`, not `pkgs_0x2EExtra`).
---@param name string
---@return string
local function fix_name(name)
	return (name:gsub("[^%w_]", function(char)
		return string.format("_0x%02X_", string.byte(char))
	end))
end

---@brief
--- Transform an injection for editing in the injected language:
---  - drop Nix `''` literal escapes (`''${x}` -> `${x}`), and
---  - rename Nix interpolations (`${pkgs.x}` -> `${pkgs_0x2E_x}`), recording the
---    original parent expression in the returned ledger.
--- Treesitter identifies the nodes (ADR-0002); the text is reconstructed from the
--- node's children. All other content is preserved verbatim.
---
---@param node TSNode The injected content node, in the parent language.
---@param bufnr integer The parent buffer the node lives in.
---@param parent_lang string The parent filetype.
---@return string text The transformed injection text.
---@return { c_var: string, p_var: string }[] ledger Interpreted placeholders, in order.
function M.forward(node, bufnr, parent_lang)
	if parent_lang ~= PARENT_LANG then
		return vim.treesitter.get_node_text(node, bufnr), {}
	end

	---@type string[]
	local parts = {}
	---@type { c_var: string, p_var: string }[]
	local ledger = {}
	for child in node:iter_children() do
		local kind = child:type()
		if kind == NIX_INTERPOLATION then
			local expr = child:named_child(0)
			local p_var = expr and vim.treesitter.get_node_text(expr, bufnr) or ""
			local c_var = fix_name(p_var)
			local c_var_expr = "${" .. c_var .. "}"
			parts[#parts + 1] = c_var_expr
			ledger[#ledger + 1] = { c_var = c_var, p_var = p_var }
		elseif kind ~= NIX_LITERAL_ESCAPE then
			-- Drop `''` literal escapes; keep everything else verbatim.
			parts[#parts + 1] = vim.treesitter.get_node_text(child, bufnr)
		end
	end
	return table.concat(parts), ledger
end

--- Injected-language Treesitter node type for a braced `${...}` expansion. Only
--- braced expansions interpolate in a Nix parent, so a bare `$VAR`
--- (`simple_expansion`) needs no escaping.
local INJECTED_EXPANSION = "expansion"

---@brief
--- Read the interpreted-placeholder ledger from a child buffer's ninjection
--- block: each `c_var=... <comment> <- p_var` line maps the child id back to its
--- original parent expression. Parses ninjection's own fenced block, not the
--- language (ADR-0002).
---@param lines string[] The child lines.
---@param inj_lang string The injected (child) language.
---@return table<string, string> ledger Map of c_var -> p_var.
function M.read_ledger(lines, inj_lang)
	local desc = HEADERS[inj_lang]
	if not desc then
		return {}
	end

	local open = desc.comment .. FENCE_OPEN
	local close = desc.comment .. FENCE_CLOSE
	local arrow = " " .. desc.comment .. FENCE_ARROW

	---@type table<string, string>
	local ledger = {}
	local in_block = false
	for _, line in ipairs(lines) do
		if line:sub(1, #open) == open then
			in_block = true
		elseif line == close then
			break
		elseif in_block then
			local pos = line:find(arrow, 1, true)
			if pos then
				local c_var = line:sub(1, pos - 1):match("^([%w_]+)")
				if c_var then
					ledger[c_var] = line:sub(pos + #arrow)
				end
			end
		end
	end
	return ledger
end

---@brief
--- Restore injected-language `${x}` expansions to their parent form for
--- write-back. An expansion whose name is an interpreted placeholder (in the
--- block ledger) is un-mangled to the bare parent interpolation `${p_var}`; any
--- other expansion is a literal and is re-escaped to `''${x}`. Treesitter finds
--- the expansions in the child buffer (ADR-0002). If the injected language has no
--- grammar / `${}`, the lines are returned unchanged.
---
---@param bufnr integer The child buffer, in the injected language.
---@param parent_lang string The parent filetype to restore escaping for.
---@return string[] lines The child lines with expansions restored to parent form.
function M.reverse(bufnr, parent_lang)
	---@type string[]
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	if parent_lang ~= PARENT_LANG then
		return lines
	end

	---@type boolean, vim.treesitter.LanguageTree?
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not ok or not parser then
		return lines
	end
	---@cast parser vim.treesitter.LanguageTree

	local inj_lang = parser:lang()
	local ledger = M.read_ledger(lines, inj_lang)

	-- The injected language may have no `${...}` expansion concept (e.g. Lua), in
	-- which case the query is invalid for its grammar; treat that as nothing to
	-- restore rather than an error.
	local q_ok, query = pcall(vim.treesitter.query.parse, inj_lang, "(" .. INJECTED_EXPANSION .. ") @e")
	if not q_ok or not query then
		return lines
	end

	local root = parser:parse()[1]:root()

	---@type { s_row: integer, s_col: integer, e_col: integer?, c_var: string? }[]
	local edits = {}
	for _, node in query:iter_captures(root, bufnr, 0, -1) do
		local s_row, s_col, e_row, e_col = node:range()
		-- Only single-line expansions are rewritten by range; multi-line ones fall
		-- back to a leading escape at the start position.
		---@type string?
		local c_var
		for child in node:iter_children() do
			if child:type() == "variable_name" then
				c_var = vim.treesitter.get_node_text(child, bufnr)
				break
			end
		end
		edits[#edits + 1] = { s_row = s_row, s_col = s_col, e_col = (s_row == e_row) and e_col or nil, c_var = c_var }
	end

	-- Apply from last to first so earlier edits don't shift later coordinates.
	table.sort(edits, function(edit_a, edit_b)
		if edit_a.s_row ~= edit_b.s_row then
			return edit_a.s_row > edit_b.s_row
		end
		return edit_a.s_col > edit_b.s_col
	end)

	for _, edit in ipairs(edits) do
		local line = lines[edit.s_row + 1]
		if edit.c_var and ledger[edit.c_var] and edit.e_col then
			-- Interpreted: replace ${c_var} with the bare parent interpolation.
			local p_var_expr = "${" .. ledger[edit.c_var] .. "}"
			line = line:sub(1, edit.s_col) .. p_var_expr .. line:sub(edit.e_col + 1)
		else
			-- Literal (or unknown): re-escape with a leading ''.
			line = line:sub(1, edit.s_col) .. "''" .. line:sub(edit.s_col + 1)
		end
		lines[edit.s_row + 1] = line
	end

	return lines
end

-- Language header (injected-keyed) ----------------------------------------
-- The header is ephemeral scaffolding prepended to the child buffer for the
-- injected language's tooling and stripped on write-back. Injected-keyed per
-- ADR-0001; declarative descriptor table (HEADERS, defined above) for now. It
-- carries the shebang Nix synthesises at build time plus a fenced "ninjection
-- block" of real declarations so the injected LSP does not flag the references.

---@brief
--- Collect the placeholder variable names declared by `${name}` expansions in
--- the child buffer, in first-seen order without duplicates. Treesitter reads
--- the names (ADR-0002); a grammar without `${}` yields none.
---@param bufnr integer The child buffer, in the injected language.
---@return string[] c_vars
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
	local c_vars = {}
	for _, node in query:iter_captures(root, bufnr, 0, -1) do
		local c_var = vim.treesitter.get_node_text(node, bufnr)
		-- Only declare valid identifiers. Shell positional (`${1}`) and special
		-- parameters are intrinsically defined and are not declarable assignments.
		if not seen[c_var] and c_var:match("^[%a_][%w_]*$") then
			seen[c_var] = true
			c_vars[#c_vars + 1] = c_var
		end
	end
	return c_vars
end

---@brief
--- Build the language-header lines: the shebang, then (when there are vars) a
--- fenced ninjection block declaring each at the injected language's default
--- value. Returns an empty list for languages without a descriptor.
---@param inj_lang string The injected (child) language.
---@param parent_lang string The parent filetype, recorded in the fence.
---@param c_vars string[] Child placeholder names to declare.
---@param ledger? { c_var: string, p_var: string }[] Interpreted placeholders; each
--- gets a `# <- p_var` arrow so write-back restores the bare parent interpolation.
---@return string[] header
function M.build_header(inj_lang, parent_lang, c_vars, ledger)
	local desc = HEADERS[inj_lang]
	if not desc then
		return {}
	end

	---@type table<string, string>
	local interp = {}
	for _, entry in ipairs(ledger or {}) do
		interp[entry.c_var] = entry.p_var
	end

	---@type string[]
	local lines = { desc.shebang }
	if c_vars and #c_vars > 0 then
		lines[#lines + 1] = desc.comment .. FENCE_OPEN .. parent_lang
		for _, c_var in ipairs(c_vars) do
			local decl = c_var .. desc.assign .. desc.default
			if interp[c_var] then
				decl = decl .. " " .. desc.comment .. FENCE_ARROW .. interp[c_var]
			end
			lines[#lines + 1] = decl
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
	for index, line in ipairs(lines) do
		if line == close then
			return vim.list_slice(lines, index + 1)
		end
	end

	if lines[1] == desc.shebang then
		return vim.list_slice(lines, 2)
	end
	return lines
end

return M
