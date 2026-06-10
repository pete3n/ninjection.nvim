---@module "ninjection.resolve"
---@brief
--- Resolution engine: produce the parent language's *actual evaluated* value for
--- an interpolation (the "Resolved value" of CONTEXT.md, deferred by ADR-0005).
--- Treesitter walks outward from the interpolation node to reconstruct the lexical
--- bindings in scope (ADR-0002: scope reconstruction is structural introspection,
--- not a job for a hand-rolled Nix parser) and synthesizes a self-contained
--- expression evaluated with `nix eval --raw --expr` against the project's pinned
--- flake input. The engine returns data; a verb renders it non-destructively
--- (ADR-0006: resolution is an engine, not a verb).

local M = {}

---@type NinjectionConfig
local cfg = setmetatable({}, {
	__index = function(_, key)
		return require("ninjection.config").values[key]
	end,
})

local ts = require("vim.treesitter")

--- Parent language whose scope semantics this engine knows. Resolution is
--- parent-keyed; only a Nix parent is implemented for the spike.
local PARENT_LANG = "nix"

--- Treesitter node type for a Nix `${expr}` interpolation.
local NIX_INTERPOLATION = "interpolation"

--- Node types walked during scope reconstruction.
local NIX_VARIABLE = "variable_expression"
local NIX_FUNCTION = "function_expression"
local NIX_FORMALS = "formals"
local NIX_FORMAL = "formal"
local NIX_LET = "let_expression"
local NIX_BINDING_SET = "binding_set"
local NIX_BINDING = "binding"

---@brief
--- The head free name an interpolation expression depends on: the leftmost
--- variable in its select/apply chain (`pkgs.hello` -> `pkgs`). Descends leftmost
--- named children until a `variable_expression` is reached.
---@param expr_node TSNode
---@param bufnr integer
---@return string? name
local function head_name(expr_node, bufnr)
	---@type TSNode?
	local node = expr_node
	while node do
		if node:type() == NIX_VARIABLE then
			return ts.get_node_text(node, bufnr)
		end
		node = node:named_child(0)
	end
	return nil
end

---@brief
--- Whether `name` is declared as a function formal (`{ name, ... }:`) on this
--- `function_expression` node.
---@param fn_node TSNode A `function_expression` node.
---@param name string
---@param bufnr integer
---@return boolean
local function declares_formal(fn_node, name, bufnr)
	for child in fn_node:iter_children() do
		if child:type() == NIX_FORMALS then
			for formal in child:iter_children() do
				if formal:type() == NIX_FORMAL then
					local id = formal:named_child(0)
					if id and ts.get_node_text(id, bufnr) == name then
						return true
					end
				end
			end
		end
	end
	return false
end

---@tag ninjection.resolve.find_interpolation()
---@brief
--- Find the innermost Nix `interpolation` node containing the cursor. The cursor
--- sits in the parent buffer, so the parent (Nix) tree is queried directly rather
--- than any injected tree.
---
---@param bufnr integer The parent buffer.
---@param cursor_pos integer[] Cursor position, (1:0) row:col indexed.
---@return TSNode? node, string? err The interpolation node, or nil + reason.
function M.find_interpolation(bufnr, cursor_pos)
	---@type integer, integer
	local row, col = cursor_pos[1] - 1, cursor_pos[2]

	---@type boolean, vim.treesitter.LanguageTree?
	local ok, parser = pcall(ts.get_parser, bufnr, PARENT_LANG, { error = false })
	if not ok or not parser then
		return nil, "ninjection.resolve.find_interpolation() error: no " .. PARENT_LANG .. " parser for buffer"
	end
	---@cast parser vim.treesitter.LanguageTree

	local root = parser:parse()[1]:root()

	---@type TSNode?
	local found
	local q_ok, query = pcall(ts.query.parse, PARENT_LANG, "(" .. NIX_INTERPOLATION .. ") @interp")
	if not q_ok or not query then
		return nil, "ninjection.resolve.find_interpolation() error: failed to parse interpolation query"
	end

	for _, node in query:iter_captures(root, bufnr, 0, -1) do
		if ts.is_in_node_range(node, row, col) then
			-- Keep the innermost (smallest) match containing the cursor.
			if not found or node:byte_length() < found:byte_length() then
				found = node
			end
		end
	end

	if not found then
		return nil, "ninjection.resolve.find_interpolation() warning: no interpolation at cursor"
	end
	return found, nil
end

---@brief
--- The text of the `let` binding for `name` on this `let_expression`, if it
--- declares one (`greeting = "hi";` for `let greeting = "hi"; in ...`). The Nix
--- `binding` node spans the trailing `;`, so it reads as a ready-to-splice clause.
---@param let_node TSNode A `let_expression` node.
---@param name string
---@param bufnr integer
---@return string? binding_text
local function let_binding_text(let_node, name, bufnr)
	for child in let_node:iter_children() do
		if child:type() == NIX_BINDING_SET then
			for binding in child:iter_children() do
				if binding:type() == NIX_BINDING then
					local attrpath = binding:named_child(0)
					if attrpath and ts.get_node_text(attrpath, bufnr) == name then
						return ts.get_node_text(binding, bufnr)
					end
				end
			end
		end
	end
	return nil
end

---@brief
--- Render the Nix preamble that supplies `pkgs` from the project's pinned flake
--- input, never the ambient `<nixpkgs>` channel (ADR-0006). A store path is
--- available at evaluation time, so resolving never realises a derivation.
---@param root_dir string Flake root whose `nixpkgs` input is the source of truth.
---@return string
local function pkgs_preamble(root_dir)
	return 'let pkgs = (builtins.getFlake "' .. root_dir .. '").inputs.nixpkgs.legacyPackages.${builtins.currentSystem}; '
end

---@tag ninjection.resolve.synthesize()
---@brief
--- Reconstruct the lexical scope of an interpolation and synthesize a
--- self-contained Nix expression for it. For an interpolation whose head name is
--- unbound in the file, `pkgs` is supplied from the pinned flake input.
---
---@param node TSNode The interpolation node, in the parent (Nix) buffer.
---@param bufnr integer The parent buffer.
---@param root_dir string Flake root whose `nixpkgs` input supplies `pkgs`.
---@return NJResolution? result, string? err
function M.synthesize(node, bufnr, root_dir)
	---@type TSNode?
	local expr_node = node:named_child(0)
	if not expr_node then
		return nil, "ninjection.resolve.synthesize() warning: interpolation has no expression"
	end

	---@type string
	local expr_text = ts.get_node_text(expr_node, bufnr)

	-- Reconstruct scope by walking outward. The *nearest* binding of the head name
	-- decides feasibility (ADR-0006): a `let`/`with`/`inherit` binding in view is
	-- self-contained (reconstruct it), a function formal lives in an unseen caller
	-- (not resolvable from the file alone), and an otherwise-unbound name falls back
	-- to `pkgs` supplied from the pinned flake input.
	---@type string?
	local name = head_name(expr_node, bufnr)
	if name then
		---@type TSNode?
		local ancestor = node:parent()
		while ancestor do
			local kind = ancestor:type()
			if kind == NIX_FUNCTION and declares_formal(ancestor, name, bufnr) then
				return { bound_by_caller = name }, nil
			elseif kind == NIX_LET then
				---@type string?
				local binding = let_binding_text(ancestor, name, bufnr)
				if binding then
					return {
						expr = "let " .. binding .. " in builtins.toString (" .. expr_text .. ")",
					}, nil
				end
			end
			ancestor = ancestor:parent()
		end
	end

	-- Head name is unbound in the file: supply `pkgs` from the pinned flake input.
	---@type NJResolution
	local result = {
		expr = pkgs_preamble(root_dir) .. "in builtins.toString (" .. expr_text .. ")",
	}
	return result, nil
end

--- The `nix eval` invocation. `--offline` avoids the substituter round-trips that
--- only matter for *building*; resolution reads store paths at evaluation time.
--- `--impure` is required because `getFlake` on a dev tree and `currentSystem` are
--- impure (ADR-0006), even though the ambient channel is never touched.
---@param expr string The synthesized expression.
---@return string[]
local function nix_eval_cmd(expr)
	return {
		"nix",
		"eval",
		"--offline",
		"--impure",
		"--extra-experimental-features",
		"nix-command flakes",
		"--raw",
		"--expr",
		expr,
	}
end

---@tag ninjection.resolve.resolve()
---@brief
--- Resolve an interpolation to its parent language's real evaluated value. The
--- scope is reconstructed and synthesized (see |ninjection.resolve.synthesize()|),
--- then evaluated with `nix eval`. A caller-bound interpolation is returned as-is
--- without evaluating. Resolution reads store paths at evaluation time and never
--- realises a derivation.
---
---@param node TSNode The interpolation node, in the parent (Nix) buffer.
---@param bufnr integer The parent buffer.
---@param root_dir string Flake root whose `nixpkgs` input supplies `pkgs`.
---@return NJResolution? result, string? err
function M.resolve(node, bufnr, root_dir)
	---@type NJResolution?, string?
	local result, syn_err = M.synthesize(node, bufnr, root_dir)
	if not result then
		return nil, syn_err
	end
	---@cast result NJResolution

	-- A caller-bound interpolation is not resolvable from the file alone; surface
	-- the condition rather than evaluating.
	if result.bound_by_caller then
		return result, nil
	end
	-- lua_ls cannot @cast a field; hoist to a local to narrow string? -> string.
	local expr = result.expr
	---@cast expr string

	---@type boolean, vim.SystemCompleted?
	local ok, completed = pcall(function()
		return vim.system(nix_eval_cmd(expr), { text = true }):wait()
	end)
	if not ok or not completed then
		---@type string
		local err = "ninjection.resolve.resolve() error: failed to invoke nix ... " .. tostring(completed)
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end
	---@cast completed vim.SystemCompleted

	if completed.code ~= 0 then
		---@type string
		local err = "ninjection.resolve.resolve() error: nix eval failed ... " .. tostring(completed.stderr)
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end

	---@type string
	local path = vim.trim(completed.stdout or "")
	if path == "" then
		return nil, "ninjection.resolve.resolve() warning: nix eval returned no value"
	end

	result.path = path
	return result, nil
end

return M
