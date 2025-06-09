---@module "ninjection"
---@brief
--- The ninjection module contains the three primary ninjection functions:
--- |select()|, |edit()|, and |replace()|.

local ninjection = {}

---@nodoc
---@param user_cfg Ninjection.Config
---@return nil
function ninjection.setup(user_cfg)
	---@type boolean, string?
	local is_valid, err
	is_valid, err = require("ninjection.health").validate_config(user_cfg)
	if is_valid == true then
		require("ninjection.config")._merge_config(user_cfg)
	else
		vim.notify(
			"ninjection warning: User configuration is invalid: "
				.. err
				.. " \nReverting to default configuration settings.",
			vim.log.levels.WARN
		)
	end
end

---@type Ninjection.Config
local cfg = require("ninjection.config").values
local buffer = require("ninjection.buffer")
local parse = require("ninjection.parse")
local NJChild = require("ninjection.child")
local NJParent = require("ninjection.parent")
local lsp = require("ninjection.lsp")

if vim.fn.exists(":checkhealth") == 2 then
	require("ninjection.health").check()
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
		vim.cmd("normal! `<V`>") -- Visual line select using marks
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

	local nj_child = NJChild.new({
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

	buffer.set_child_cur({
		win = nj_child.c_win,
		p_cursor = injection.cursor_pos,
		s_row = (injection.range.s_row + cur_row_offset),
		indents = cfg.preserve_indents and nj_child.p_indents or nil,
		text_meta = injection.text_meta,
	})

	---@type NJLspStatus?, string?
	local c_lsp, lsp_err = lsp.start_lsp(injection.pair.inj_lang, root_dir, nj_child.c_bufnr)
	if not c_lsp or c_lsp.status == lsp.LspStatusMsg then
		---@type string
		local err = "ninjection.edit() warning: starting LSP failed ... " .. tostring(lsp_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		-- Don't return early on LSP failure
	end
	---@cast c_lsp NJLspStatus
	if c_lsp and not c_lsp:is_attached(nj_child.c_bufnr) then
		if cfg.debug then
			vim.notify(
				"ninjection.edit() warning: LSP failed to attach to buffer: " .. nj_child.c_bufnr,
				vim.log.levels.WARN
			)
			-- Don't return early on LSP failure
		end
	end

	-- Track parent, child buffer relations, in the event multiple child buffers
	-- are opened for the same injected content.
	-- Retrieve the existing ninjection table or initialize a new one
	---@type boolean, string?
	local reg_ok, reg_err = buffer.reg_child_buf(nj_child.p_bufnr, nj_child.c_bufnr)
	if not reg_ok then
		---@type string
		local err = "ninjection.edit() error: Failed to register child buffer with parent..." .. tostring(reg_err)
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
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
	local nj_child, child_err = buffer.get_buf_child(cur_bufnr)
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
	---@type string[]
	local rep_lines = get_lines_return

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

	if cfg.debug then
		if not cfg.inj_text_restorers then
			vim.notify("cfg.inj_text_restorers is nil", vim.log.levels.WARN)
		elseif not cfg.inj_text_restorers[nj_child.p_ft] then
			vim.notify("No restorer defined for filetype: " .. tostring(nj_child.p_ft), vim.log.levels.WARN)
		elseif not nj_child.p_text_meta then
			vim.notify("text_meta is nil for current injection", vim.log.levels.WARN)
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

	---@type boolean
	local del_buf_ok = pcall(vim.api.nvim_buf_delete, cur_bufnr, { force = true })
	if not del_buf_ok then
		---@type string
		local err = "ninjection.replace() warning: Failed to delete child buffer: " .. cur_bufnr
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return true, err
	end

	nj_parent:del_child(cur_bufnr)
	nj_parent:set_nj_table(nj_child.p_bufnr)

	-- Calculate tentative row and col based on config
	---@type integer, integer
	local row = this_cursor[1] + nj_child.p_range.s_row
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

---@tag indent_block()
---@brief
--- Re-indents a block of lines and surrounding delimiters ('' and '';
--- for a given injection range and replacement text.
---
--- Parameters ~
---@param bufnr integer - Buffer handle to operate on
---@param range NJRange - Injection range { s_row, e_row }
---@param rep_lines string[] - Formatted injected code
---
--- Notes ~
--- Assumes the line before s_row is the parent indent base.
local function indent_block(bufnr, range, rep_lines)
	local s_row = range.s_row
	local e_row = range.e_row

	-- Get parent indent from the line above the start row
	local parent_line = vim.api.nvim_buf_get_lines(bufnr, s_row - 1, s_row, false)[1] or ""
	local parent_indent = parent_line:match("^(%s*)") or ""

	-- Compute indents
	local delimiter_indent = parent_indent .. string.rep(" ", cfg.format_indent)
	local child_indent = delimiter_indent .. string.rep(" ", cfg.format_indent)

	-- Construct replacement lines
	local formatted_lines = {}
	table.insert(formatted_lines, delimiter_indent .. "''")
	for _, line in ipairs(rep_lines) do
		table.insert(formatted_lines, child_indent .. line)
	end
	table.insert(formatted_lines, delimiter_indent .. "'';")

	-- Replace full block (including delimiters)
	vim.api.nvim_buf_set_lines(bufnr, s_row, e_row + 1, false, formatted_lines)
end

local function is_buf_visible(bufnr)
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == bufnr then
			return true
		end
	end
	return false
end

---@tag ninjection.format()
---@brief
--- Formats the injected code block under cursor using a specified format cmd,
--- Sets indentation based on existing indents and configurable offsets.
---
--- @return boolean success, string? err
function ninjection.format()
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

	---@type NJChild
	local nj_child = NJChild.new({
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
		return false, tostring(init_err)
	end

	---@type NJLspStatus?, string?
	local lsp_status, lsp_err = lsp.start_lsp(injection.pair.inj_lang, root_dir, nj_child.c_bufnr)
	if not lsp_status then
		-- start_lsp should always return a status
		return false, tostring(lsp_err)
	end
	---@cast lsp_status NJLspStatus
	if lsp_status.status ~= lsp.LspStatusMsg.STARTED then
		if cfg.debug then
			---@type string
			local err = "ninjection.format() warning: starting LSP failed... " .. tostring(lsp_err)
			vim.notify(err, vim.log.levels.WARN)
			-- Don't return early on LSP start failure
		end
	end
	---@cast lsp_status NJLspStatus

	require("conform").format({
		bufnr = nj_child.c_bufnr,
		async = true,
		lsp_fallback = true,
		timeout_ms = 3000,
	}, function()
		local rep_lines = vim.api.nvim_buf_get_lines(nj_child.c_bufnr, 0, -1, false)
		if not rep_lines or #rep_lines == 0 then
			vim.notify("No formatted output", vim.log.levels.WARN)
		else
			indent_block(cur_bufnr, injection.range, rep_lines)
		end

		for _, win in ipairs(vim.api.nvim_list_wins()) do
			local buf = vim.api.nvim_win_get_buf(win)
			vim.notify("Window " .. win .. " has buffer " .. buf)
		end

		vim.defer_fn(function()
			-- Defer deletion to allow LSP background operations to finish
			if nj_child.c_bufnr and vim.api.nvim_buf_is_valid(nj_child.c_bufnr) then
				vim.api.nvim_buf_delete(nj_child.c_bufnr, { force = true })
			end
		end, 150) -- ~150ms delay to avoid race with semantic token requests
	end)

	return true, nil
end

return ninjection
