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
local NIX_INHERIT = "inherit"
local NIX_INHERIT_FROM = "inherit_from"
local NIX_APPLY = "apply_expression"
local NIX_PATH = "path_expression"
local NIX_ATTRSET = "attrset_expression"
local NIX_LIST = "list_expression"

---@brief
--- The head free name an interpolation expression depends on: the leftmost
--- variable in its select/apply chain (`pkgs.hello` -> `pkgs`). Descends leftmost
--- named children until a `variable_expression` is reached.
---@param expr_node TSNode
---@param source integer|string Buffer number or source text the node was parsed from.
---@return string? name
local function head_name(expr_node, source)
	---@type TSNode?
	local node = expr_node
	while node do
		if node:type() == NIX_VARIABLE then
			return ts.get_node_text(node, source)
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
---@param source integer|string Buffer number or source text the node was parsed from.
---@return boolean
local function declares_formal(fn_node, name, source)
	for child in fn_node:iter_children() do
		if child:type() == NIX_FORMALS then
			for formal in child:iter_children() do
				if formal:type() == NIX_FORMAL then
					local id = formal:named_child(0)
					if id and ts.get_node_text(id, source) == name then
						return true
					end
				end
			end
		end
	end
	return false
end

---@brief
--- Root of the parent-language tree for `bufnr`, or nil when the buffer has no
--- parent parser.
---@param bufnr integer
---@return TSNode? root
local function parent_tree_root(bufnr)
	---@type boolean, vim.treesitter.LanguageTree?
	local ok, parser = pcall(ts.get_parser, bufnr, PARENT_LANG, { error = false })
	if not ok or not parser then
		return nil
	end
	---@cast parser vim.treesitter.LanguageTree
	return parser:parse()[1]:root()
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

	---@type TSNode?
	local root = parent_tree_root(bufnr)
	if not root then
		return nil, "ninjection.resolve.find_interpolation() error: no " .. PARENT_LANG .. " parser for buffer"
	end

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

---@tag ninjection.resolve.find_resolvable()
---@brief
--- Find the resolvable node at the cursor: the innermost Nix `interpolation`
--- containing it, or — outside any interpolation — the bare variable expression
--- under the cursor (e.g. `wget` in `with pkgs; [ wget ]`). Attribute-path
--- names are not variable expressions, so a cursor on a binding name finds
--- nothing.
---
---@param bufnr integer The parent buffer.
---@param cursor_pos integer[] Cursor position, (1:0) row:col indexed.
---@return TSNode? node, string? err The resolvable node, or nil + reason.
function M.find_resolvable(bufnr, cursor_pos)
	---@type TSNode?
	local interp = M.find_interpolation(bufnr, cursor_pos)
	if interp then
		return interp, nil
	end

	---@type integer, integer
	local row, col = cursor_pos[1] - 1, cursor_pos[2]
	---@type TSNode?
	local root = parent_tree_root(bufnr)
	if not root then
		return nil, "ninjection.resolve.find_resolvable() error: no " .. PARENT_LANG .. " parser for buffer"
	end

	---@type TSNode?
	local at_cursor = root:named_descendant_for_range(row, col, row, col)
	while at_cursor and at_cursor:type() ~= NIX_VARIABLE do
		at_cursor = at_cursor:parent()
	end
	if at_cursor then
		return at_cursor, nil
	end
	return nil, "ninjection.resolve.find_resolvable() warning: no resolvable expression at cursor"
end

---@brief
--- Whether this inherit clause (`inherit a b;` / `inherit (src) a b;`) names
--- `name` among its inherited attrs.
---@param inherit_node TSNode An `inherit` or `inherit_from` node.
---@param name string
---@param source integer|string Buffer number or source text the node was parsed from.
---@return boolean
local function inherits_name(inherit_node, name, source)
	---@type TSNode?
	local attrs = inherit_node:field("attrs")[1]
	if not attrs then
		return false
	end
	for attr in attrs:iter_children() do
		if attr:named() and ts.get_node_text(attr, source) == name then
			return true
		end
	end
	return false
end

---@brief
--- The `let` binding for `name` on this `let_expression`, if it declares one —
--- a plain binding (`greeting = "hi";`) or an inherit-from clause
--- (`inherit (src) greeting;`). Either node spans the trailing `;`, so its text
--- reads as a ready-to-splice clause; the node itself is also returned so a
--- caller can keep tracing the binding's value expression. A plain
--- `inherit greeting;` only re-binds the enclosing scope, so it supplies no
--- value and is passed over.
---@param let_node TSNode A `let_expression` node.
---@param name string
---@param source integer|string Buffer number or source text the node was parsed from.
---@return string? binding_text, TSNode? binding_node
local function let_binding_text(let_node, name, source)
	for child in let_node:iter_children() do
		if child:type() == NIX_BINDING_SET then
			for binding in child:iter_children() do
				if binding:type() == NIX_BINDING then
					local attrpath = binding:named_child(0)
					if attrpath and ts.get_node_text(attrpath, source) == name then
						return ts.get_node_text(binding, source), binding
					end
				elseif binding:type() == NIX_INHERIT_FROM and inherits_name(binding, name, source) then
					return ts.get_node_text(binding, source), binding
				end
			end
		end
	end
	return nil, nil
end

---@brief
--- The nearest lexical binding of `name` in view — a function formal or a `let`
--- binding on an ancestor — walking outward from `start`. Lexical bindings are
--- what `with` cannot shadow (Nix scoping). A `let` binding also yields its
--- ready-to-splice clause text and node; a formal is bound but has no in-file
--- clause.
---@param start TSNode
---@param name string
---@param source integer|string Buffer number or source text the node was parsed from.
---@return ("formal"|"let")? binding_kind, string? let_clause, TSNode? binding_node
local function lexical_binding(start, name, source)
	---@type TSNode?
	local ancestor = start:parent()
	while ancestor do
		local kind = ancestor:type()
		if kind == NIX_FUNCTION and declares_formal(ancestor, name, source) then
			return "formal", nil, nil
		elseif kind == NIX_LET then
			---@type string?, TSNode?
			local binding_text, binding_node = let_binding_text(ancestor, name, source)
			if binding_text then
				return "let", binding_text, binding_node
			end
		end
		ancestor = ancestor:parent()
	end
	return nil, nil, nil
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

---@brief
--- Render a `let ... in ` clause binding `name` to the flake input of the same
--- name. Inside flake.nix the outputs function is applied to the locked inputs,
--- so a name "bound by the caller" there *is* addressable — this is where a
--- caller-binding chain bottoms out (ADR-0006).
---@param name string
---@param root_dir string Flake root.
---@return string
local function input_clause(name, root_dir)
	return "let " .. name .. ' = (builtins.getFlake "' .. root_dir .. '").inputs.' .. name .. "; in "
end

---@brief
--- The argument attrset of the call site instantiating `parent_file` —
--- an `import ./<file> { ... }` application whose path resolves to it.
---@param flake_root TSNode Root of the parsed flake.nix tree.
---@param source string The flake.nix source text.
---@param parent_file string Absolute path of the instantiated file.
---@param root_dir string Flake root, for resolving the relative import path.
---@return TSNode? call_args
local function find_call_site(flake_root, source, parent_file, root_dir)
	---@type boolean, vim.treesitter.Query?
	local q_ok, query = pcall(ts.query.parse, PARENT_LANG, "(" .. NIX_APPLY .. ") @apply")
	if not q_ok or not query then
		return nil
	end
	for _, apply in query:iter_captures(flake_root, source, 0, -1) do
		---@type TSNode?, TSNode?
		local fn, args = apply:field("function")[1], apply:field("argument")[1]
		if fn and fn:type() == NIX_APPLY and args and args:type() == NIX_ATTRSET then
			---@type TSNode?, TSNode?
			local import_fn, import_path = fn:field("function")[1], fn:field("argument")[1]
			if
				import_fn
				and import_fn:type() == NIX_VARIABLE
				and ts.get_node_text(import_fn, source) == "import"
				and import_path
				and import_path:type() == NIX_PATH
			then
				---@type string
				local resolved = vim.fs.normalize(root_dir .. "/" .. ts.get_node_text(import_path, source))
				if resolved == vim.fs.normalize(parent_file) then
					return args
				end
			end
		end
	end
	return nil
end

---@brief
--- How a call-site argument attrset supplies `name`: a plain inherit
--- (`inherit pkgs;` — the caller's variable of the same name) or an explicit
--- binding (`lib = pkgs.lib;` — an expression in the caller's scope).
---@param args_node TSNode The call site's `attrset_expression`.
---@param name string
---@param source integer|string Buffer number or source text the node was parsed from.
---@return ("inherit"|"binding")? arg_kind, TSNode? arg_node
local function call_arg(args_node, name, source)
	for child in args_node:iter_children() do
		if child:type() == NIX_BINDING_SET then
			for binding in child:iter_children() do
				if binding:type() == NIX_BINDING then
					local attrpath = binding:named_child(0)
					if attrpath and ts.get_node_text(attrpath, source) == name then
						return "binding", binding
					end
				elseif binding:type() == NIX_INHERIT and inherits_name(binding, name, source) then
					return "inherit", binding
				end
			end
		end
	end
	return nil, nil
end

---@brief
--- The call site instantiating `parent_file` as a *module*: an application
--- (`nixpkgs.lib.nixosSystem { ... }`) whose argument attrset has a `modules`
--- list containing a path that resolves to it. Returns the apply node and its
--- argument attrset.
---@param flake_root TSNode Root of the parsed flake.nix tree.
---@param source string The flake.nix source text.
---@param parent_file string Absolute path of the instantiated file.
---@param root_dir string Flake root, for resolving the relative module path.
---@return TSNode? apply, TSNode? call_args
local function find_module_call_site(flake_root, source, parent_file, root_dir)
	---@type boolean, vim.treesitter.Query?
	local q_ok, query = pcall(ts.query.parse, PARENT_LANG, "(" .. NIX_APPLY .. ") @apply")
	if not q_ok or not query then
		return nil, nil
	end
	for _, apply in query:iter_captures(flake_root, source, 0, -1) do
		---@type TSNode?
		local args = apply:field("argument")[1]
		if args and args:type() == NIX_ATTRSET then
			---@type ("inherit"|"binding")?, TSNode?
			local modules_kind, modules_binding = call_arg(args, "modules", source)
			if modules_kind == "binding" and modules_binding then
				---@type TSNode?
				local modules_list = modules_binding:field("expression")[1]
				if modules_list and modules_list:type() == NIX_LIST then
					for element in modules_list:iter_children() do
						if element:type() == NIX_PATH then
							---@type string
							local resolved = vim.fs.normalize(root_dir .. "/" .. ts.get_node_text(element, source))
							if resolved == vim.fs.normalize(parent_file) then
								return apply, args
							end
						end
					end
				end
			end
		end
	end
	return nil, nil
end

---@brief
--- Trace `name` outward from `start` through the flake.nix scope until it
--- bottoms out at a flake input, accumulating ready-to-splice `let ... in `
--- clauses (outermost first). Each hop splices the nearest `let` binding and
--- continues with the head name of that binding's value expression; a formal
--- means the outputs function's argument — a flake input — and closes the
--- chain. An unbound head or a binding cycle yields nil.
---@param start TSNode
---@param name string
---@param source string The flake.nix source text.
---@param root_dir string Flake root.
---@return string? clauses
local function trace_to_input(start, name, source, root_dir)
	---@type string[]
	local clauses = {}
	---@type table<string, boolean>
	local seen = {}
	---@type TSNode?, string?
	local node, head = start, name
	while node and head and not seen[head] do
		seen[head] = true
		---@type ("formal"|"let")?, string?, TSNode?
		local binding_kind, clause, binding_node = lexical_binding(node, head, source)
		if binding_kind == "formal" then
			table.insert(clauses, 1, input_clause(head, root_dir))
			return table.concat(clauses)
		elseif clause and binding_node then
			table.insert(clauses, 1, "let " .. clause .. " in ")
			---@type TSNode?
			local value = binding_node:field("expression")[1]
			node, head = binding_node, value and head_name(value, source) or nil
		else
			return nil
		end
	end
	return nil
end

---@brief
--- Reconstruct the `pkgs` a module-system call supplies to its modules:
--- `<input>.legacyPackages.<system>`, where the input is traced from the head
--- of the callee (`nixpkgs` in `nixpkgs.lib.nixosSystem`) and the system is
--- read from the call site's `system` binding (`builtins.currentSystem` when
--- the call declares none). Returns the ready-to-splice `let ... in ` chain.
---@param apply TSNode The module-system `apply_expression` node.
---@param call_args TSNode The call's argument `attrset_expression`.
---@param source string The flake.nix source text.
---@param root_dir string Flake root.
---@return string? clauses
local function module_pkgs_clauses(apply, call_args, source, root_dir)
	---@type TSNode?
	local callee = apply:field("function")[1]
	---@type string?
	local head = callee and head_name(callee, source) or nil
	if not head then
		return nil
	end
	---@type string?
	local outer = trace_to_input(apply, head, source, root_dir)
	if not outer then
		return nil
	end

	---@type ("inherit"|"binding")?, TSNode?
	local system_kind, system_binding = call_arg(call_args, "system", source)
	---@type string
	local system_text = "builtins.currentSystem"
	if system_kind == "binding" and system_binding then
		---@type TSNode?
		local system_expr = system_binding:field("expression")[1]
		if system_expr then
			system_text = ts.get_node_text(system_expr, source)
		end
	end
	return outer .. "let pkgs = " .. head .. ".legacyPackages.${" .. system_text .. "}; in "
end

---@brief
--- Reconstruct the caller's binding chain for a formal of `parent_file` from
--- the flake call site: parse `<root_dir>/flake.nix`, find the
--- `import ./<file> { ... }` instantiation, and trace the argument supplying
--- the formal back to a flake input. Returns the ready-to-splice `let ... in `
--- chain, or nil when the caller is not in view (no flake, no call site, the
--- formal is not supplied, or the chain never reaches an input) — the genuine
--- bound-by-caller condition.
---@param formal_name string
---@param parent_file string Absolute path of the buffer's file.
---@param root_dir string Flake root.
---@return string? clauses
local function caller_clauses(formal_name, parent_file, root_dir)
	---@type string
	local flake_path = root_dir .. "/flake.nix"
	if vim.fn.filereadable(flake_path) == 0 then
		return nil
	end
	---@type string
	local source = table.concat(vim.fn.readfile(flake_path), "\n")
	---@type boolean, vim.treesitter.LanguageTree?
	local ok, parser = pcall(ts.get_string_parser, source, PARENT_LANG)
	if not ok or not parser then
		return nil
	end
	---@cast parser vim.treesitter.LanguageTree
	---@type TSNode
	local flake_root = parser:parse()[1]:root()

	---@type TSNode?
	local call_args = find_call_site(flake_root, source, parent_file, root_dir)
	if not call_args then
		-- Not import-instantiated; the file may instead be a *module* of a
		-- `lib.nixosSystem`-shaped call, where the module system (not the call's
		-- attrset) supplies `pkgs`. Only `pkgs` is reconstructible that way —
		-- other module arguments (`config`, `lib`) would need a module-system
		-- evaluation.
		if formal_name ~= "pkgs" then
			return nil
		end
		---@type TSNode?, TSNode?
		local apply, module_args = find_module_call_site(flake_root, source, parent_file, root_dir)
		if not apply or not module_args then
			return nil
		end
		return module_pkgs_clauses(apply, module_args, source, root_dir)
	end

	---@type ("inherit"|"binding")?, TSNode?
	local arg_kind, arg_node = call_arg(call_args, formal_name, source)
	if arg_kind == "inherit" and arg_node then
		-- `inherit pkgs;`: the formal is the caller's variable of the same name.
		return trace_to_input(arg_node, formal_name, source, root_dir)
	elseif arg_kind == "binding" and arg_node then
		-- `lib = pkgs.lib;`: splice the binding verbatim as the innermost clause
		-- and trace its value expression's head through the caller's scope.
		---@type TSNode?
		local value = arg_node:field("expression")[1]
		---@type string?
		local head = value and head_name(value, source) or nil
		if not head then
			return nil
		end
		---@type string?
		local outer = trace_to_input(arg_node, head, source, root_dir)
		if not outer then
			return nil
		end
		return outer .. "let " .. ts.get_node_text(arg_node, source) .. " in "
	end
	return nil
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
	-- An interpolation wraps its expression; a bare expression node (e.g. a
	-- variable in a `with pkgs; [ ... ]` list) *is* the expression.
	---@type TSNode?
	local expr_node = node:type() == NIX_INTERPOLATION and node:named_child(0) or node
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
			-- The binding lives in an unseen caller — unless the caller is the
			-- project flake itself: when flake.nix instantiates this file and
			-- supplies the formal, the chain bottoms out at a flake input and
			-- closes (ADR-0006's "knowing how the file is instantiated").
			---@type string?
			local clauses = caller_clauses(name, vim.api.nvim_buf_get_name(bufnr), root_dir)
			if clauses then
				return { expr = clauses .. "builtins.toString (" .. expr_text .. ")" }, nil
			end
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
				elseif binding_kind == "formal" then
					-- The environment's value lives in an unseen caller — unless
					-- the project flake instantiates this file and supplies the
					-- formal (same bottoming-out as an interpolation head formal).
					---@type string?
					local env_clauses = caller_clauses(env_name, vim.api.nvim_buf_get_name(bufnr), root_dir)
					if not env_clauses then
						return { bound_by_caller = env_name }, nil
					end
					table.insert(clauses, env_clauses)
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
