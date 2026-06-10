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
local NIX_WITH = "with_expression"
local NIX_BINDING_SET = "binding_set"
local NIX_BINDING = "binding"
local NIX_INHERIT_FROM = "inherit_from"

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
--- Whether this `inherit_from` clause (`inherit (src) a b;`) inherits `name`.
---@param inherit_node TSNode An `inherit_from` node.
---@param name string
---@param bufnr integer
---@return boolean
local function inherits_name(inherit_node, name, bufnr)
	---@type TSNode?
	local attrs = inherit_node:field("attrs")[1]
	if not attrs then
		return false
	end
	for attr in attrs:iter_children() do
		if attr:named() and ts.get_node_text(attr, bufnr) == name then
			return true
		end
	end
	return false
end

---@brief
--- The text of the `let` binding for `name` on this `let_expression`, if it
--- declares one — a plain binding (`greeting = "hi";`) or an inherit-from
--- clause (`inherit (src) greeting;`). Either node spans the trailing `;`, so
--- it reads as a ready-to-splice clause. A plain `inherit greeting;` only
--- re-binds the enclosing scope, so it supplies no value and is passed over.
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
				elseif binding:type() == NIX_INHERIT_FROM and inherits_name(binding, name, bufnr) then
					return ts.get_node_text(binding, bufnr)
				end
			end
		end
	end
	return nil
end

---@brief
--- The nearest lexical binding of `name` in view — a function formal or a `let`
--- binding on an ancestor — walking outward from `start`. Lexical bindings are
--- what `with` cannot shadow (Nix scoping). A `let` binding also yields its
--- ready-to-splice clause text; a formal is bound but has no in-file clause.
---@param start TSNode
---@param name string
---@param bufnr integer
---@return ("formal"|"let")? binding_kind, string? let_clause
local function lexical_binding(start, name, bufnr)
	---@type TSNode?
	local ancestor = start:parent()
	while ancestor do
		local kind = ancestor:type()
		if kind == NIX_FUNCTION and declares_formal(ancestor, name, bufnr) then
			return "formal", nil
		elseif kind == NIX_LET then
			---@type string?
			local binding = let_binding_text(ancestor, name, bufnr)
			if binding then
				return "let", binding
			end
		end
		ancestor = ancestor:parent()
	end
	return nil, nil
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
	-- to `pkgs` supplied from the pinned flake input. A lexical binding wins over
	-- any `with`, regardless of nesting order (Nix scoping), so the lexical lookup
	-- runs first and `with` environments only matter when it comes up empty.
	---@type string?
	local name = head_name(expr_node, bufnr)
	-- Enclosing `with` environments, innermost first.
	---@type TSNode[]
	local with_envs = {}
	if name then
		---@type ("formal"|"let")?, string?
		local binding_kind, let_clause = lexical_binding(node, name, bufnr)
		if binding_kind == "formal" then
			return { bound_by_caller = name }, nil
		elseif let_clause then
			return {
				expr = "let " .. let_clause .. " in builtins.toString (" .. expr_text .. ")",
			}, nil
		end

		---@type TSNode?
		local ancestor = node:parent()
		while ancestor do
			if ancestor:type() == NIX_WITH then
				---@type TSNode?
				local env = ancestor:field("environment")[1]
				if env then
					table.insert(with_envs, env)
				end
			end
			ancestor = ancestor:parent()
		end
	end

	if #with_envs > 0 then
		-- Inner `with` shadows outer: emit outermost first so the innermost
		-- clause sits nearest the expression. An environment whose own head name
		-- is let-bound in view gets that binding reconstructed ahead of the
		-- chain; one lexically unbound in the file gets `pkgs` from the pinned
		-- flake input, same as an unbound interpolation head.
		---@type string[]
		local clauses = {}
		---@type boolean
		local env_unbound = false
		for env_index = #with_envs, 1, -1 do
			---@type TSNode
			local env = with_envs[env_index]
			---@type string?
			local env_name = head_name(env, bufnr)
			if env_name then
				---@type ("formal"|"let")?, string?
				local binding_kind, let_clause = lexical_binding(env, env_name, bufnr)
				if not binding_kind then
					env_unbound = true
				elseif let_clause then
					table.insert(clauses, "let " .. let_clause .. " in ")
				end
			end
			table.insert(clauses, "with " .. ts.get_node_text(env, bufnr) .. "; ")
		end
		---@type string
		local preamble = env_unbound and (pkgs_preamble(root_dir) .. "in ") or ""
		---@type NJResolution
		local with_result = {
			expr = preamble .. table.concat(clauses) .. "builtins.toString (" .. expr_text .. ")",
		}
		return with_result, nil
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

---@brief
--- Hand a resolution to `on_done` on the main loop, never synchronously — the
--- async contract holds even for conditions known before an eval is spawned, and
--- the eval's completion callback runs off the main loop where API calls are
--- unsafe. An error is also surfaced as a debug diagnostic.
---@param on_done fun(result: NJResolution?, err: string?)
---@param result NJResolution?
---@param err string?
local function deliver(on_done, result, err)
	vim.schedule(function()
		if err and cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		on_done(result, err)
	end)
end

---@tag ninjection.resolve.resolve()
---@brief
--- Resolve an interpolation to its parent language's real evaluated value. The
--- scope is reconstructed and synthesized (see |ninjection.resolve.synthesize()|),
--- then evaluated with `nix eval`. A caller-bound interpolation is delivered as-is
--- without evaluating. Resolution reads store paths at evaluation time and never
--- realises a derivation.
---
--- The eval runs asynchronously so a cold/online `nix eval` never blocks the
--- editor; `on_done` receives the result on the main loop, never synchronously
--- (even for conditions known before the eval is spawned).
---
---@param node TSNode The interpolation node, in the parent (Nix) buffer.
---@param bufnr integer The parent buffer.
---@param root_dir string Flake root whose `nixpkgs` input supplies `pkgs`.
---@param on_done fun(result: NJResolution?, err: string?) Receives the resolution.
function M.resolve(node, bufnr, root_dir, on_done)
	---@type NJResolution?, string?
	local result, syn_err = M.synthesize(node, bufnr, root_dir)
	if not result then
		return deliver(on_done, nil, syn_err)
	end
	---@cast result NJResolution

	-- A caller-bound interpolation is not resolvable from the file alone; surface
	-- the condition rather than evaluating.
	if result.bound_by_caller then
		return deliver(on_done, result, nil)
	end
	-- lua_ls cannot @cast a field; hoist to a local to narrow string? -> string.
	local expr = result.expr
	---@cast expr string

	---@type boolean, any
	local spawn_ok, spawn_err = pcall(vim.system, nix_eval_cmd(expr), { text = true }, function(completed)
		if completed.code ~= 0 then
			return deliver(
				on_done,
				nil,
				"ninjection.resolve.resolve() error: nix eval failed ... " .. tostring(completed.stderr)
			)
		end

		---@type string
		local path = vim.trim(completed.stdout or "")
		if path == "" then
			return deliver(on_done, nil, "ninjection.resolve.resolve() warning: nix eval returned no value")
		end

		result.path = path
		deliver(on_done, result, nil)
	end)
	if not spawn_ok then
		deliver(on_done, nil, "ninjection.resolve.resolve() error: failed to invoke nix ... " .. tostring(spawn_err))
	end
end

return M
