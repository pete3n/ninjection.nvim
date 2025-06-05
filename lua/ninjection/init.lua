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

---@nodoc
---@return string root_dir Root directory for new buffer
local function get_root_dir()
	-- Try getting the workspace folders list first
	---@type boolean, unknown?
	local ok, folders = pcall(vim.lsp.buf.list_workspace_folders)
	if ok and type(folders) == "table" and type(folders[1]) == "string" and folders[1] ~= "" then
		return folders[1]
	end

	-- Fallback to the current working directory
	---@type string?
	local cwd
	ok, cwd = pcall(vim.fn.getcwd)
	if ok and type(cwd) == "string" and cwd ~= "" then
		return cwd
	end

	error("ninjection.init.get_root_dir() error: Could not determine root dir.", 2)
end

---@tag ninjection.edit()
---@brief
--- Detects injected languages at the cursor position and begins editing supported
--- languages according to configured preferences. `ninjection.edit()` creates a
--- child buffer with an `NJChild` object that stores config information for itself
--- and information to replace text in the parent buffer. It also appends the child
--- buffer handle to an `NJParent` object in the parent buffer.
---
---@return nil
---
function ninjection.edit()
	---@type boolean, unknown?
	local ok, result
	ok, result = pcall(vim.api.nvim_get_current_buf)
	if not ok then
		error(tostring(result))
	end
	if type(result) ~= "number" then
		error("ninjection.edit() error: Could not retrieve current buffer handle.")
	end
	---@type integer
	local cur_bufnr = result

	---@type NJNodeTable?, string?
	local injection, err
	injection, err = parse.get_injection(cur_bufnr)
	if not injection then
		if cfg.debug then
			vim.notify("ninjection.edit() warning: Failed to get injected node " .. tostring(err), vim.log.levels.WARN)
		end
		return nil
	end
	---@cast injection NJNodeTable

	---@type string
	local root_dir = get_root_dir()

	ok, result = pcall(vim.api.nvim_buf_get_name, 0)
	if not ok then
		error(tostring(result), 2)
	end
	if type(result) ~= "string" then
		if cfg.debug then
			vim.notify(
				"ninjection.edit() warning: No name returned from " .. "vim.api.nvim_buf_get_name(0)",
				vim.log.levels.WARN
			)
		end
		return nil
	end
	---@type string
	local buf_name = result

	-- Apply filetype specific text modification functions
	if cfg.inj_text_modifiers and cfg.inj_text_modifiers[injection.ft] then
		vim.notify("Calling injection_text modifier for: " .. injection.ft)
		injection.text, injection.text_meta = cfg.inj_text_modifiers[injection.ft](injection.text)
	end

	---@type NJChild
	local new_child = {
		ft = injection.pair.inj_lang, -- The injected language becomes the child ft
		root_dir = root_dir, -- Child inherits the root directory of the parent
		p_bufnr = cur_bufnr, -- The parent buffer will be the current buffer
		p_name = buf_name, -- The parent buffer name will be the current buffer name
		p_ft = injection.ft, -- The parent filetype is the current filetype
		p_range = injection.range, -- The parent range is the current injection range
		p_text_meta = injection.text_meta, -- Metadata of modifications made to original text
	}

	---@type {bufnr: integer?, win: integer?, indents: NJIndents}
	local c_table

	c_table, err = buffer.create_child(new_child, injection.text)
	if not c_table.bufnr or not c_table.win then
		error("ninjection.edit() error: Could not create child buffer and window: " .. tostring(err), 2)
	end

	---@type integer
	local row_offset = 0
	if injection.text_meta.removed_leading == true then
		row_offset = 1
	end

	buffer.set_child_cur({
		win = c_table.win,
		p_cursor = injection.cursor_pos,
		s_row = (injection.range.s_row + row_offset),
		indents = cfg.preserve_indents and c_table.indents or nil,
		text_meta = injection.text_meta,
	})

	---@type NJLspStatus?
	local lsp_info
	lsp_info, err = buffer.start_lsp(injection.pair.inj_lang, root_dir, c_table.bufnr)
	if not lsp_info then
		if cfg.debug and err then
			vim.notify("ninjection.edit() warning: starting LSP failed: " .. err, vim.log.levels.WARN)
			-- Don't return early on LSP failure
		end
	end
	if lsp_info and not lsp_info:is_attached(c_table.bufnr) then
		if cfg.debug and err then
			vim.notify(
				"ninjection.edit() warning: LSP failed to attach to buffer: " .. c_table.bufnr,
				vim.log.levels.WARN
			)
			-- Don't return early on LSP failure
		end
	end

	-- Track parent, child buffer relations, in the event multiple child buffers
	-- are opened for the same injected content.
	-- Retrieve the existing ninjection table or initialize a new one
	---@type NJParent
	local p_ninjection
	ok, result = pcall(function()
		return vim.api.nvim_buf_get_var(cur_bufnr, "ninjection")
	end)
	if ok and type(result) == "table" then
		p_ninjection = result
	else
		err = tostring(result)
		if err:find("Key not found: ninjection") then
			p_ninjection = { children = {} }
		else
			error(err)
		end
	end
	p_ninjection.children = p_ninjection.children or {}

	-- Append the new child_bufnr to the children array.
	table.insert(p_ninjection.children, c_table.bufnr)

	-- Write it back to the buffer variable.
	ok, result = pcall(function()
		return vim.api.nvim_buf_set_var(cur_bufnr, "ninjection", p_ninjection)
	end)
	if not ok then
		error(tostring(result), 2)
	end

	return nil
end

-- NOTE: Child buffer should not close on error

---@tag ninjection.replace()
---@brief
--- Replaces the original injected language text in the parent buffer
--- with the current buffer text. This state is stored by in the `vim.b.ninjection`
--- table as an `NJParent` table in the child, and `NJChild` table indexed by the
--- child bufnr in the parent. This relationship is validated before replacing.
---
---@return nil
---
function ninjection.replace()
	---@type boolean, unknown, string?
	local ok, result, err

	ok, result = pcall(function()
		return vim.api.nvim_get_current_buf()
	end)
	if not ok then
		error(tostring(result), 2)
	end
	if type(result) ~= "number" then
		error(
			"ninjection.replace() error: Could not retrieve a buffer handle "
				.. "calling vim.api.nvim_get_current_buf().",
			2
		)
	end
	---@type integer
	local cur_bufnr = result

	-- We need to validate that the current buffer has a parent buffer, and that the
	-- parent buffer has the current buffer as a child.
	ok, result = pcall(function()
		return vim.api.nvim_buf_get_var(cur_bufnr, "ninjection")
	end)
	if not ok or type(result) ~= "table" then
		err = tostring(result)
		if err:find("Key not found: ninjection") then
			if cfg.debug then
				vim.notify(
					"ninjection.replace() warning: This buffer is not a valid " .. "ninjection buffer.",
					vim.log.levels.WARN
				)
			end
			return nil
		else
			error("ninjection.replace() error: Could not retrieve ninjection table " .. "from child buffer." .. err, 2)
		end
	end
	---@type NJChild
	local nj_child_b = result
	if not nj_child_b.p_bufnr then
		error("ninjection.replace() error: Could not retrieve valid parent buffer for this buffer.", 2)
	end

	ok, result = pcall(function()
		return vim.api.nvim_buf_get_var(nj_child_b.p_bufnr, "ninjection")
	end)
	if not ok or type(result) ~= "table" then
		err = tostring(result)
		if err:find("Key not found: ninjection") then
			error(
				"ninjection.replace() error: This buffer appears to be an orphan. "
					.. "The recorded parent has no ninjection table.",
				2
			)
		end
		error("ninjection.replace() error: Could not retrieve ninjection table " .. "for parent buffer." .. err, 2)
	end
	---@type NJParent
	local nj_parent_b = result
	if not vim.tbl_contains(nj_parent_b.children, cur_bufnr) then
		error("ninjection.replace() error: The recorded parent buffer has no record of this buffer.", 2)
	end
	---@cast nj_parent_b NJParent

	ok, result = pcall(function()
		return vim.api.nvim_win_get_cursor(0)
	end)
	if not ok or type(result) ~= "table" then
		error(tostring(result), 2)
	end
	---@type integer[]
	local this_cursor = result
	if not this_cursor[2] then
		if cfg.debug then
			vim.notify(
				"ninjection.replace() warning: No child cursor values returned by vim.api.nvim_win_get_cursor(0)",
				vim.log.levels.WARN
			)
		end
	end
	if not nj_child_b.p_range then
		error("ninjection.replace() error: missing parent buffer range values. Cannot sync changes.", 2)
	end

	ok, result = pcall(function()
		return vim.api.nvim_buf_get_lines(0, 0, -1, false)
	end)
	if not ok or type(result) ~= "table" then
		error(tostring(result), 2)
	end
	---@type string[]
	local rep_text = result
	if not rep_text or #rep_text == 0 then
		if cfg.debug then
			vim.notify(
				"ninjection.replace() warning: No replacement text returned " .. "by vim.api.nvim_buf_get_lines()",
				vim.log.levels.WARN
			)
		end
		return nil
	end

	if cfg.preserve_indents then
		result, err = buffer.restore_indents(rep_text, nj_child_b.p_indents)
		if not result or type(result) ~= "table" then
			if cfg.debug then
				vim.notify(
					"ninjection.replace() warning: buffer.restore_indents() could not restore indents: " .. err,
					vim.log.levels.WARN
				)
			end
		else
			rep_text = result
		end
	end

	if cfg.debug then
		vim.notify("Debug: Checking conditions for inj_text_restorers...", vim.log.levels.INFO)

		if not cfg.inj_text_restorers then
			vim.notify("cfg.inj_text_restorers is nil", vim.log.levels.WARN)
		elseif not cfg.inj_text_restorers[nj_child_b.p_ft] then
			vim.notify("No restorer defined for filetype: " .. tostring(nj_child_b.p_ft), vim.log.levels.WARN)
		elseif not nj_child_b.p_text_meta then
			vim.notify("text_meta is nil for current injection", vim.log.levels.WARN)
		else
			vim.notify("Calling restorer for: " .. nj_child_b.p_ft, vim.log.levels.WARN)
			---@type string
			local rep_lines = table.concat(rep_text, "\n")
			ok, result =
				pcall(cfg.inj_text_restorers[nj_child_b.p_ft], rep_lines, nj_child_b.p_text_meta, nj_child_b.p_indents)

			if not ok then
				vim.notify("Error calling restorer: " .. tostring(result), vim.log.levels.ERROR)
			else
				vim.notify("Restorer executed successfully", vim.log.levels.INFO)
				rep_text = result
			end
		end
	end

	ok, result = pcall(function()
		return vim.api.nvim_buf_set_text(
			nj_child_b.p_bufnr,
			nj_child_b.p_range.s_row,
			nj_child_b.p_range.s_col,
			nj_child_b.p_range.e_row,
			nj_child_b.p_range.e_col,
			rep_text
		)
	end)
	if not ok then
		error(tostring(result), 2)
	end

	ok, result = pcall(function()
		return vim.cmd("bdelete!")
	end)
	if not ok then
		error(tostring(result), 2)
	end

	-- Remove the child entry in the parent after deleting the buffer
	nj_parent_b.children[cur_bufnr] = nil
	ok, result = pcall(function()
		return vim.api.nvim_buf_set_var(nj_child_b.p_bufnr, "ninjection", nj_parent_b)
	end)
	if not ok then
		err = tostring(result)
		if cfg.debug then
			vim.notify(
				"ninjection.replace() warning: could not remove child buffer "
					.. "entry from parent buffer after deleting buffer."
					.. err,
				vim.log.levels.WARN
			)
		end
	end

	ok, result = pcall(function()
		return vim.api.nvim_set_current_buf(nj_child_b.p_bufnr)
	end)
	if not ok then
		error(tostring(result), 2)
	end

	-- Reset the cursor to the same relative position in the parent buffer
	---@type integer[]
	local pos
	if cfg.preserve_indents then
		pos = {
			this_cursor[1] + nj_child_b.p_range.s_row,
			this_cursor[2] + nj_child_b.p_indents.l_indent,
		}
	else
		pos = { this_cursor[1] + nj_child_b.p_range.s_row, this_cursor[2] }
	end

	ok, result = pcall(function()
		return vim.api.nvim_win_set_cursor(0, pos)
	end)
	if not ok then
		err = tostring(result)
		if cfg.debug then
			vim.notify(
				"ninjection.replace() warning: could not restore cursor position in the parent buffer." .. err,
				vim.log.levels.WARN
			)
		end
	end
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

---@tag ninjection.format()
---@brief
--- Formats the injected code block under cursor using a specified format cmd,
--- Sets indentation based on existing indents and configurable offsets.
---
--- Requires `cfg.format_cmd` and `cfg.format_indent` to be set.
---
--- @return nil
function ninjection.format()
	---@type boolean, unknown?
	local ok, result
	ok, result = pcall(vim.api.nvim_get_current_buf)
	if not ok then
		error(tostring(result))
	end
	if type(result) ~= "number" then
		error("ninjection.edit() error: Could not retrieve current buffer handle.")
	end
	---@type integer
	local cur_bufnr = result

	---@type NJNodeTable?, string?
	local injection, err
	injection, err = parse.get_injection(cur_bufnr)
	if not injection then
		if cfg.debug then
			vim.notify("ninjection.edit() warning: Failed to get injected node " .. tostring(err), vim.log.levels.WARN)
		end
		return nil
	end
	---@cast injection NJNodeTable

	---@type string
	local root_dir = get_root_dir()

	ok, result = pcall(vim.api.nvim_buf_get_name, 0)
	if not ok then
		error(tostring(result), 2)
	end
	if type(result) ~= "string" then
		if cfg.debug then
			vim.notify(
				"ninjection.edit() warning: No name returned from " .. "vim.api.nvim_buf_get_name(0)",
				vim.log.levels.WARN
			)
		end
		return nil
	end
	---@type string
	local buf_name = result

	-- Apply filetype specific text modification functions
	if cfg.inj_text_modifiers and cfg.inj_text_modifiers[injection.ft] then
		vim.notify("Calling injection_text modifier for: " .. injection.ft)
		injection.text, injection.text_meta = cfg.inj_text_modifiers[injection.ft](injection.text)
	end

	---@type NJChild
	local new_child = {
		ft = injection.pair.inj_lang, -- The injected language becomes the child ft
		root_dir = root_dir, -- Child inherits the root directory of the parent
		p_bufnr = cur_bufnr, -- The parent buffer will be the current buffer
		p_name = buf_name, -- The parent buffer name will be the current buffer name
		p_ft = injection.ft, -- The parent filetype is the current filetype
		p_range = injection.range, -- The parent range is the current injection range
		p_text_meta = injection.text_meta, -- Metadata of modifications made to original text
	}

	---@type {bufnr: integer?, win: integer?, indents: NJIndents}
	local c_table

	c_table, err = buffer.create_child(new_child, injection.text)
	if not c_table.bufnr or not c_table.win then
		error("ninjection.edit() error: Could not create child buffer and window: " .. tostring(err), 2)
	end

	vim.notify("Child bufnr: " .. tostring(c_table.bufnr))
	vim.notify("Injected text: " .. injection.text)
	vim.notify("Requested LSP start for bufnr: " .. c_table.bufnr)

	---@type NJLspStatus?
	local lsp_info
	ok, lsp_info, err = pcall(buffer.start_lsp, injection.pair.inj_lang, root_dir, c_table.bufnr)
	if not ok then
		vim.notify(
			"start_lsp threw error: " .. tostring(lsp_info) .. tostring(err),
			vim.log.levels.ERROR,
			{ title = "Ninjection error" }
		)
		return nil
	end
	if lsp_info and lsp_info.status ~= "started" then
		if cfg.debug then
			vim.notify("ninjection.edit() warning: starting LSP " .. err, vim.log.levels.WARN)
			-- Don't return early on LSP failure
		end
	end
	---@cast lsp_info NJLspStatus
	vim.notify("LSP status is: " .. lsp_info.status)

	--TODO: move to cfg format options
	local timeout_ms = 5000
	local interval_ms = 50
	local elapsed_ms = 0

	local client = vim.lsp.get_client_by_id(lsp_info.client_id)
	if client then
		vim.notify("LSP client found: " .. client.name .. " (id: " .. client.id .. ")", vim.log.levels.DEBUG)
		if not client.attached_buffers[c_table.bufnr] then
			vim.notify("Attaching client " .. client.name .. " to bufnr: " .. c_table.bufnr, vim.log.levels.DEBUG)
			vim.lsp.buf_attach_client(c_table.bufnr, lsp_info.client_id)
		else
			vim.notify("Client already attached to bufnr: " .. c_table.bufnr, vim.log.levels.DEBUG)
		end
	else
		vim.notify("No LSP client found for id: " .. tostring(lsp_info.client_id), vim.log.levels.WARN)
	end

	while not lsp_info:is_attached(c_table.bufnr) and elapsed_ms < timeout_ms do
		vim.wait(interval_ms)
		elapsed_ms = elapsed_ms + interval_ms
	end

	if not lsp_info:is_attached(c_table.bufnr) then
		vim.notify("LSP did not fully initialize within timeout for bufnr: " .. c_table.bufnr, vim.log.levels.WARN)
	else
		vim.notify("LSP successfully attached to bufnr: " .. c_table.bufnr, vim.log.levels.INFO)
	end

	---@type string[]?
	local rep_lines
	ok, rep_lines = pcall(function()
		return vim.api.nvim_buf_get_lines(c_table.bufnr, 0, -1, false)
	end)
	if not ok or type(rep_lines) ~= "table" then
		vim.notify(
			"ninjection.format() error: No lines captured from formatting buffer ... " .. tostring(rep_lines),
			vim.log.levels.ERROR
		)
	end
	---@cast rep_lines string[]
	if not rep_lines or #rep_lines == 0 then
		if cfg.debug then
			vim.notify(
				"ninjection.replace() warning: No formatted text returned " .. "by vim.api.nvim_buf_get_lines()",
				vim.log.levels.WARN
			)
		end
		return nil
	end

	vim.notify("Current bufnr: " .. vim.inspect(cur_bufnr))
	vim.notify("Replacement text: " .. table.concat(rep_lines, "\n"))

	if rep_lines and #rep_lines > 0 and lsp_info:is_attached(c_table.bufnr) then
		indent_block(cur_bufnr, injection.range, rep_lines)
	else
		vim.notify("Skipping indent block: no formatted output or LSP not ready", vim.log.levels.WARN)
	end

	-- Close child window if it still exists
	if c_table.win and vim.api.nvim_win_is_valid(c_table.win) then
		vim.api.nvim_win_close(c_table.win, true)
	end

	-- Wipe child buffer if it still exists
	if c_table.bufnr and vim.api.nvim_buf_is_valid(c_table.bufnr) then
		vim.api.nvim_buf_delete(c_table.bufnr, { force = true })
	end
	return nil
end

return ninjection
