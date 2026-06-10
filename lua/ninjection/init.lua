---@module "ninjection"
---@brief
--- The ninjection module contains the three primary ninjection functions:
--- |select()|, |edit()|, and |replace()|.

local ninjection = {}

---@nodoc
---@param user_cfg NinjectionConfig
---@return nil
function ninjection.setup(user_cfg)
	---@type boolean, string[]?
	local is_valid_cfg, cfg_errors = require("ninjection.config")._merge_config(user_cfg)

	if not is_valid_cfg then
		vim.notify(
			"ninjection.setup() warning: Reverted to default_config. Invalid user configuration:\n"
				.. table.concat(vim.tbl_map(tostring, cfg_errors or {}), "\n"),
			vim.log.levels.WARN
		)
	end
end

---@type NinjectionConfig
local cfg = setmetatable({}, {
	__index = function(_, key)
		return require("ninjection.config").values[key]
	end,
	__newindex = function(_, key, value)
		require("ninjection.config").values[key] = value
	end,
})

local buffer = require("ninjection.buffer")
local parse = require("ninjection.parse")
local resolve = require("ninjection.resolve")
local NJChild = require("ninjection.child")
local NJParent = require("ninjection.parent")
local lsp = require("ninjection.lsp")

--- Namespace for the non-destructive resolution overlay (virtual text). Resolved
--- values are surfaced here, never written into the buffer (ADR-0006).
local resolve_ns = vim.api.nvim_create_namespace("ninjection_resolve")

if vim.fn.exists(":checkhealth") == 2 and vim.health and vim.health.report_info then
	---@type boolean, string?
	local ok, err = pcall(function()
		require("ninjection.health").check()
	end)
	if not ok then
		vim.notify("ninjection.init() error: health check failed: " .. tostring(err), vim.log.levels.ERROR)
	end
end

---@tag ninjection.select()
---@brief
--- Identifies and selects injected text in visual line mode.
---
---@return nil
function ninjection.select()
	local bufnr = vim.api.nvim_get_current_buf()
	if type(bufnr) ~= "number" then
		if cfg.debug then
			vim.notify("ninjection.select() warning: Could not get current buffer", vim.log.levels.WARN)
		end
		return nil
	end

	---@type NJNodeTable?
	local injection, err = parse.get_injection(bufnr)
	if not injection or not injection.pair.node then
		if cfg.debug then
			vim.notify("ninjection.select() warning: No valid TSNode returned: " .. tostring(err), vim.log.levels.WARN)
		end
		return nil
	end

	---@type NJRange?
	local v_range
	v_range, err = parse.get_visual_range(injection.pair.node, bufnr)
	if not v_range then
		if cfg.debug then
			vim.notify("ninjection.select() warning: no visual range returned: " .. tostring(err), vim.log.levels.WARN)
		end
		return nil
	end

	-- Select full lines using linewise visual mode
	-- TODO: Implement non-line selection with column positions
	local ok, result = pcall(function()
		vim.fn.setpos("'<", { 0, v_range.s_row + 1, 1, 0 }) -- start at beginning of start line
		vim.fn.setpos("'>", { 0, v_range.e_row + 1, 1, 0 }) -- end at beginning of end line

		-- Visual line mode selection
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("`<V`>", true, false, true), "x", false)
	end)

	if not ok then
		error("ninjection.select() error: " .. tostring(result), 2)
	end

	return nil
end

---@tag ninjection.edit()
---@brief
--- Detects injected languages at the cursor position and begins editing supported
--- languages according to configured preferences. `ninjection.edit()` creates a
--- child buffer with an `NJChild` object that stores config information for itself
--- and information to replace text in the parent buffer. It also appends the child
--- buffer handle to an `NJParent` object in the parent buffer.
---
---@return boolean success, string? err
---
function ninjection.edit()
	---@type NJParent, NJChild
	local nj_parent, nj_child

	---@type boolean, integer?
	local get_cbuf_ok, cur_bufnr
	get_cbuf_ok, cur_bufnr = pcall(vim.api.nvim_get_current_buf)
	if not get_cbuf_ok or type(cur_bufnr) ~= "number" then
		---@type string
		local err = "ninjection.edit() error: Could not retrieve current buffer handle."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
	end
	---@cast cur_bufnr integer

	---@type NJNodeTable?, string?
	local injection, inj_err
	injection, inj_err = parse.get_injection(cur_bufnr)
	if not injection then
		---@type string
		local err = "ninjection.edit() warning: Failed to get injected node ... " .. tostring(inj_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return false, err
	end
	---@cast injection NJNodeTable

	-- Transform parent placeholders for editing (de-escape ''${x} -> ${x}, rename
	-- interpolations ${pkgs.x} -> ${pkgs_0x2E_x}) using Treesitter before any
	-- string-level modifiers run, so the injected language sees valid syntax. The
	-- ledger records the interpreted placeholders for the header block.
	-- See docs/adr/0001-0002.
	local placeholder = require("ninjection.placeholder")
	---@type { c_var: string, p_var: string }[]
	local interp_ledger
	injection.text, interp_ledger = placeholder.forward(injection.pair.node, cur_bufnr, injection.ft)

	-- Apply filetype specific text modification functions
	---@type integer
	local cur_row_offset = 0
	if cfg.inj_text_modifiers and cfg.inj_text_modifiers[injection.ft] then
		injection.text, injection.text_meta = cfg.inj_text_modifiers[injection.ft](injection.text)
		-- Adjust the cursor offset if the leading line was removed
		if injection.text_meta.removed_leading == true then
			cur_row_offset = 1
		end
	end

	---@type string?, string?
	local root_dir, dir_err = buffer.get_root_dir()
	if not root_dir then
		---@type string
		local err = "ninjection.edit() error: Failed to get current working directory ... " .. tostring(dir_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end
	---@cast root_dir string

	---@type boolean, string?
	local name_ok, buf_name = pcall(vim.api.nvim_buf_get_name, 0)
	if not name_ok or type(buf_name) ~= "string" then
		---@type string
		local err = "ninjection.edit() error: Failed to get current buffer's name"
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return false, err
	end
	---@cast buf_name string

	-- Don't overwrite an existing parent if it exists
	local cur_parent = buffer.get_njparent(cur_bufnr)
	if cur_parent then
		nj_parent = cur_parent
	else
		nj_parent = NJParent.new({
			p_bufnr = cur_bufnr,
			p_ft = injection.ft,
			p_name = buf_name,
		})
	end

	nj_child = NJChild.new({
		c_ft = injection.pair.inj_lang, -- The injected language becomes the child ft
		c_root_dir = root_dir, -- Child inherits the root directory of the parent
		p_bufnr = cur_bufnr, -- The parent buffer will be the current buffer
		p_name = buf_name, -- The parent buffer name will be the current buffer name
		p_ft = injection.ft, -- The parent filetype is the current filetype
		p_range = injection.range, -- The parent range is the current injection range
		p_text_meta = injection.text_meta, -- Metadata of modifications made to original text
	})

	---@type boolean, string?
	local init_ok, init_err = nj_child:init_buf({ text = injection.text, create_win = true })
	if not init_ok then
		---@type string
		local err = "ninjection.edit() error: Could not initialize Ninjection child ... " .. tostring(init_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	---@type boolean, string?
	local add_child_ok, add_child_err = nj_parent:add_child(nj_child.c_bufnr)
	if not add_child_ok then
		vim.notify(tostring(add_child_err), vim.log.levels.ERROR)
		return false, add_child_err
	end

	-- Prepend the injected-language header (ephemeral scaffolding for the child's
	-- tooling; stripped on write-back). Added after init_buf's dedent so the
	-- header never participates in indent detection. Placeholder vars are read
	-- from the de-escaped child body and declared in the fenced block so the
	-- injected LSP does not flag them. See docs/adr/0001.
	---@type string[]
	local header = placeholder.build_header(
		nj_child.c_ft,
		nj_child.p_ft,
		placeholder.collect_placeholders(nj_child.c_bufnr),
		interp_ledger
	)
	if #header > 0 then
		vim.api.nvim_buf_set_lines(nj_child.c_bufnr, 0, 0, false, header)
	end

	nj_child:set_cursor({
		p_cursor = injection.cursor_pos,
		s_row = (injection.range.s_row + cur_row_offset),
		indents = cfg.preserve_indents and nj_child.p_indents or nil,
		text_meta = injection.text_meta,
		header_lines = #header,
	})

	---@type NJLspStatus?, string?
	local c_lsp, lsp_err = lsp.start_lsp(injection.pair.inj_lang, nj_child.c_bufnr, nj_child.c_root_dir)
	if not c_lsp or c_lsp.status == lsp.LspStatusMsg then
		---@type string
		local err = "ninjection.edit() warning: starting LSP failed ... " .. tostring(lsp_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		-- Don't return early on LSP failure
	else
		-- Wait for LSP to attach
		---@type boolean
		local lsp_attach_ok = vim.wait(cfg.lsp_timeout, function()
			return c_lsp:is_attached(nj_child.c_bufnr)
		end, 50)

		if not lsp_attach_ok and cfg.debug then
			vim.notify("ninjection.edit() warning: Timeout waiting for LSP to attach.", vim.log.levels.WARN)
		end

		if cfg.auto_format then
			nj_child:format()
		end
	end

	return true, nil
end

---@tag ninjection.replace()
---@brief
--- Replaces the original injected language text in the parent buffer
--- with the current buffer text. This state is stored by in the `vim.b.ninjection`
--- table as an `NJParent` table in the child, and `NJChild` table indexed by the
--- child bufnr in the parent. This relationship is validated before replacing.
---
---@return boolean success, string? err
---
function ninjection.replace()
	---@type boolean, integer?
	local get_buf_ok, cur_bufnr = pcall(function()
		return vim.api.nvim_get_current_buf()
	end)
	if not get_buf_ok or type(cur_bufnr) ~= "number" then
		---@type string
		local err = "ninjection.replace() error: Could not retrieve current buffer handle."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end
	---@cast cur_bufnr integer

	---@type NJChild?, string?
	local nj_child, child_err = buffer.get_njchild(cur_bufnr)
	if not NJChild.is_child(nj_child) then
		return false, tostring(child_err)
	end
	---@cast nj_child NJChild

	---@type NJParent?, string?
	local nj_parent, parent_err = nj_child:get_parent()
	if not NJParent.is_parent(nj_parent) then
		return false, tostring(parent_err)
	end
	---@cast nj_parent NJParent

	---@type boolean, table?
	local get_cur_ok, cur_pos = pcall(function()
		return vim.api.nvim_win_get_cursor(0)
	end)
	if not get_cur_ok or type(cur_pos) ~= "table" or not cur_pos[2] then
		local err = "ninjection.replace() error: Unabled to get cursor position for current window."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return false, err
	end
	---@type integer[]
	local this_cursor = cur_pos

	---@type boolean, table?
	local get_lines_ok, get_lines_return = pcall(function()
		return vim.api.nvim_buf_get_lines(0, 0, -1, false)
	end)
	if not get_lines_ok or type(get_lines_return) ~= "table" or #get_lines_return == 0 then
		---@type string
		local err = "ninjection.replace() error: Unable to retrieve text from current buffer."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end
	---@cast get_lines_return string[]

	-- Re-escape injected-language ${x} expansions back to parent literals (''${x})
	-- using Treesitter, before indent restoration so node coordinates map to the
	-- raw child lines. See docs/adr/0001-0002.
	---@type string[]
	local rep_lines = require("ninjection.placeholder").reverse(0, nj_child.p_ft)

	-- Strip the ephemeral language header (shebang/block) prepended on edit, so it
	-- never reaches the parent buffer. The number of lines removed is the header
	-- height, used below to map the child cursor back to the parent. See
	-- docs/adr/0001.
	---@type string[]
	local stripped = require("ninjection.placeholder").strip_header(rep_lines, nj_child.c_ft)
	---@type integer
	local header_lines = #rep_lines - #stripped
	rep_lines = stripped

	if cfg.preserve_indents then
		---@type string[]?, string?
		local restored_lines, restore_err = buffer.restore_indents(rep_lines, nj_child.p_indents)
		if not restored_lines or type(restored_lines) ~= "table" then
			---@type string
			local err = "ninjection.replace() warning: Could not restore indents: " .. restore_err
			if cfg.debug then
				vim.notify(err, vim.log.levels.WARN)
			end
			return false, err
		end
		---@cast restored_lines string[]
		rep_lines = restored_lines
	end

	-- Restore the parent's outer string delimiters (e.g. Nix ''...'') that the
	-- inj_text_modifier stripped for editing. The write-back range covers the
	-- whole injected node including those delimiters, so this restore is
	-- load-bearing for every round-trip; it must run regardless of `cfg.debug`,
	-- which gates only verbose diagnostics. See docs/adr/0001.
	if not cfg.inj_text_restorers then
		if cfg.debug then
			vim.notify("cfg.inj_text_restorers is nil", vim.log.levels.WARN)
		end
	elseif not cfg.inj_text_restorers[nj_child.p_ft] then
		if cfg.debug then
			vim.notify("No restorer defined for filetype: " .. tostring(nj_child.p_ft), vim.log.levels.WARN)
		end
	elseif not nj_child.p_text_meta then
		if cfg.debug then
			vim.notify("text_meta is nil for current injection", vim.log.levels.WARN)
		end
	else
		---@type string
		local rep_text = table.concat(rep_lines, "\n")
		---@type boolean, string[]?
		local restored_ok, restored_text =
			pcall(cfg.inj_text_restorers[nj_child.p_ft], rep_text, nj_child.p_text_meta, nj_child.p_indents)
		if not restored_ok or not restored_text or type(restored_text) ~= "table" then
			---@type string
			local err = "ninjection.replace() error: Text restorer function for "
				.. nj_child.p_ft
				.. " failed ..."
				.. tostring(restored_text)
			if cfg.debug then
				vim.notify(err, vim.log.levels.ERROR)
			end
			return false, err
		else
			rep_lines = restored_text
		end
	end

	---@type boolean
	local set_text_ok = pcall(function()
		return vim.api.nvim_buf_set_text(
			nj_child.p_bufnr,
			nj_child.p_range.s_row,
			nj_child.p_range.s_col,
			nj_child.p_range.e_row,
			nj_child.p_range.e_col,
			rep_lines
		)
	end)

	if not set_text_ok then
		---@type string
		local err = "ninjection.replace() error: Failed to set replacement text in parent buffer: " .. nj_child.p_bufnr
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	nj_parent:del_child(cur_bufnr)

	-- Calculate tentative row and col based on config. Subtract the header height
	-- so the child cursor (which sits below the prepended header) maps back to the
	-- corresponding parent line rather than overshooting by the header size.
	---@type integer, integer
	local row = math.max(1, this_cursor[1] - header_lines) + nj_child.p_range.s_row
	local col = this_cursor[2]

	if cfg.preserve_indents and nj_child.p_indents then
		col = col + nj_child.p_indents.l_indent
	end

	-- Clamp the row to the last line of the buffer
	---@type integer
	local max_row = vim.api.nvim_buf_line_count(nj_child.p_bufnr)
	row = math.max(0, math.min(row, max_row - 1))

	-- Clamp the col to the length of the target line
	---@type string
	local line_text = vim.api.nvim_buf_get_lines(nj_child.p_bufnr, row, row + 1, false)[1] or ""
	col = math.max(0, math.min(col, #line_text))

	---@type boolean
	local cur_ok = pcall(function()
		return vim.api.nvim_win_set_cursor(0, { row + 1, col }) -- +1 for 1-based index
	end)
	if not cur_ok and cfg.debug then
		vim.notify(
			"ninjection.replace() warning: could not restore cursor position in the parent buffer.",
			vim.log.levels.WARN
		)
	end

	return true, nil
end

---@tag ninjection.format()
---@brief
--- Formats the injected code block under cursor using a specified format cmd,
--- Sets indentation based on existing indents and configurable offsets.
---
--- @return boolean success, string? err
function ninjection.format()
	---@type NJParent, NJChild
	local nj_parent, nj_child

	---@type boolean, integer?
	local cbuf_ok, cur_bufnr
	cbuf_ok, cur_bufnr = pcall(vim.api.nvim_get_current_buf)
	if not cbuf_ok or type(cur_bufnr) ~= "number" then
		---@type string
		local err = "ninjection.format() error: Could not retrieve current buffer handle."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end
	---@cast cur_bufnr integer

	---@type NJNodeTable?, string?
	local injection, inj_err
	injection, inj_err = parse.get_injection(cur_bufnr)
	if not injection then
		---@type string
		local err = "ninjection.format() warning: Failed to get injected node " .. tostring(inj_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return false, err
	end
	---@cast injection NJNodeTable

	---@type string?, string?
	local root_dir, root_err = buffer.get_root_dir()
	if not root_dir or type(root_dir) ~= "string" then
		return false, tostring(root_err)
	end
	---@cast root_dir string

	---@type boolean, string?
	local get_name_ok, buf_name = pcall(vim.api.nvim_buf_get_name, 0)
	if not get_name_ok or type(buf_name) ~= "string" then
		---@type string
		local err = "ninjection.format() warning: No name detected for current buffer."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return false, err
	end
	---@cast buf_name string

	if cfg.inj_text_modifiers and cfg.inj_text_modifiers[injection.ft] then
		injection.text, injection.text_meta = cfg.inj_text_modifiers[injection.ft](injection.text)
	end

	-- Don't overwrite an existing parent if it exists
	local cur_parent = buffer.get_njparent(cur_bufnr)
	if cur_parent then
		nj_parent = cur_parent
	else
		nj_parent = NJParent.new({
			p_bufnr = cur_bufnr,
			p_ft = injection.ft,
			p_name = buf_name,
		})
	end

	---@type NJChild
	nj_child = NJChild.new({
		c_ft = injection.pair.inj_lang, -- The injected language becomes the child ft
		c_root_dir = root_dir, -- Child inherits the root directory of the parent
		p_bufnr = cur_bufnr,
		p_name = buf_name, -- The parent buffer name will be the current buffer name
		p_ft = injection.ft,
		p_range = injection.range, -- The parent range is the current injection range
		p_text_meta = injection.text_meta, -- Metadata of modifications made to original text
	})

	---@type boolean, string?
	local init_ok, init_err = nj_child:init_buf({ text = injection.text, create_win = true })
	if not init_ok then
		return false, tostring(init_err)
	end
	nj_parent:add_child(nj_child.c_bufnr)

	---@type NJLspStatus?, string?
	local lsp_status, lsp_err = lsp.start_lsp(injection.pair.inj_lang, nj_child.c_bufnr, nj_child.c_root_dir)
	if not lsp_status then
		-- start_lsp should always return a status
		return false, tostring(lsp_err)
	end
	---@cast lsp_status NJLspStatus
	if lsp_status.status ~= lsp.LspStatusMsg.STARTED then
		if cfg.debug then
			---@type string
			local err = "ninjection.format() error: starting LSP failed... " .. tostring(lsp_err)
			vim.notify(err, vim.log.levels.ERROR)
			-- Don't return early on LSP start failure
		end
	end
	---@cast lsp_status NJLspStatus

	-- Wait for LSP to attach
	---@type boolean
	local lsp_attach_ok = vim.wait(cfg.lsp_timeout, function()
		return lsp_status:is_attached(nj_child.c_bufnr)
	end, 50)

	if not lsp_attach_ok then
		vim.notify("ninjection.format() error: Timeout waiting for LSP to attach.", vim.log.levels.ERROR)
	end

	nj_child:format()
	---@type string[]
	local formatted_lines = vim.api.nvim_buf_get_lines(nj_child.c_bufnr, 0, -1, false)
	nj_parent:replace_range(formatted_lines, injection.range)

	vim.api.nvim_win_hide(nj_child.c_win)
	nj_parent:del_child(nj_child.c_bufnr)

	return true, nil
end

---@tag ninjection.resolve()
---@brief
--- Resolves the parent interpolation under the cursor to its real evaluated value
--- and surfaces it non-destructively as virtual text at the end of the line. The
--- buffer is never mutated (ADR-0006). When the interpolation is bound by an unseen
--- caller (e.g. a `{ pkgs }:` formal), that condition is shown instead of a value.
--- This verb renders the |ninjection.resolve.resolve()| engine's data.
---
---@return boolean success, string? err
function ninjection.resolve()
	---@type boolean, integer?
	local get_buf_ok, cur_bufnr = pcall(vim.api.nvim_get_current_buf)
	if not get_buf_ok or type(cur_bufnr) ~= "number" then
		---@type string
		local err = "ninjection.resolve() error: Could not retrieve current buffer handle."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end
	---@cast cur_bufnr integer

	---@type integer[]
	local cursor_pos = vim.api.nvim_win_get_cursor(0)

	---@type TSNode?, string?
	local node, find_err = resolve.find_interpolation(cur_bufnr, cursor_pos)
	if not node then
		---@type string
		local err = "ninjection.resolve() warning: No interpolation at cursor ... " .. tostring(find_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return false, err
	end
	---@cast node TSNode

	---@type string?, string?
	local root_dir, dir_err = buffer.get_root_dir()
	if not root_dir then
		---@type string
		local err = "ninjection.resolve() error: Failed to get root directory ... " .. tostring(dir_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end
	---@cast root_dir string

	-- The node's range is read before dispatching: the eval is asynchronous and the
	-- node may be invalidated by a reparse before the result arrives.
	---@type integer
	local s_row, _, _, _ = node:range()

	resolve.resolve(node, cur_bufnr, root_dir, function(result, res_err)
		if not result then
			---@type string
			local err = "ninjection.resolve() error: resolution failed ... " .. tostring(res_err)
			if cfg.debug then
				vim.notify(err, vim.log.levels.ERROR)
			end
			return
		end
		---@cast result NJResolution

		-- Render at the end of the interpolation's line. Clear any prior overlay
		-- first so repeated resolves replace rather than stack.
		vim.api.nvim_buf_clear_namespace(cur_bufnr, resolve_ns, s_row, s_row + 1)

		---@type string
		local label
		if result.bound_by_caller then
			label = "⟨bound by caller: " .. result.bound_by_caller .. "⟩"
		else
			label = "⟶ " .. tostring(result.path)
		end

		pcall(vim.api.nvim_buf_set_extmark, cur_bufnr, resolve_ns, s_row, 0, {
			virt_text = { { label, "Comment" } },
			virt_text_pos = "eol",
		})
	end)

	return true, nil
end

return ninjection
