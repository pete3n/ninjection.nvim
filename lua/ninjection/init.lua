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
--- Identifies and selects injected text in visual mode.
---
---@return nil
---
function ninjection.select()
	---@type boolean, unknown, string?, integer?, NJNodeTable?
	local ok, raw_output, err, bufnr, node_info

	ok, raw_output = pcall(function()
		return vim.api.nvim_get_current_buf()
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	if type(raw_output) ~= "number" then
		if cfg.debug then
			vim.notify(
				"ninjection.select() warning: Could not get current buffer " .. "calling vim.api.nvim_get_current_buf()",
				vim.log.levels.WARN
			)
		end
		return nil
	end
	bufnr = raw_output
	---@cast bufnr integer

	node_info, err = parse.get_node_table(bufnr)
	if not node_info then
		if cfg.debug then
			vim.notify("ninjection.select() warning: could not retrieve TSNode: " .. tostring(err), vim.log.levels.WARN)
		end
		return nil
	end
	if not node_info.node then
		if cfg.debug then
			vim.notify("ninjection.select() warning: No valid TSNode returned.", vim.log.levels.WARN)
		end
		return nil
	end

	---@type NJRange?
	local v_range
	v_range, err = parse.get_visual_range(node_info.node, bufnr)
	if not v_range then
		if cfg.debug then
			vim.notify("ninjection.select() warning: no visual range returned: " .. tostring(err), vim.log.levels.WARN)
		end
		return nil
	end

	-- Set marks to select ranges with a custom offset
	ok, raw_output = pcall(function()
		return vim.fn.setpos("'<", { 0, v_range.s_row + 2, v_range.s_col + 1, 0 })
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end

	ok, raw_output = pcall(function()
		return vim.fn.setpos("'>", { 0, v_range.e_row, v_range.e_col - 1, 0 })
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end

	ok, raw_output = pcall(function()
		vim.cmd("normal! gv")
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end

	return nil
end

---@nodoc
---@return string root_dir Root directory for new buffer
local function get_root_dir()
	-- Try getting the workspace folders list first
	---@type boolean, unknown?
	local ok, folders = pcall(vim.lsp.buf.list_workspace_folders)
	if ok and type(folders) == "table" and type(folders[1]) == "string" and
		folders[1] ~= "" then return folders[1]
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
	local p_bufnr = result

	---@type NJNodeTable?, string?
	local injection, err
	injection, err = parse.get_injection(p_bufnr)
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
	local p_name = result

	---@type {bufnr: integer?, win: integer?, indents: NJIndents}
	local c_table
	c_table, err =
		buffer.create_child(p_bufnr, p_name, injection.range, root_dir, injection.text, injection.pair.inj_lang)
	if not c_table.bufnr or not c_table.win then
		error("ninjection.edit() error: Could not create child buffer and window: " .. tostring(err), 2)
	end

	if cfg.preserve_indents then
		buffer.set_child_cur(c_table.win, injection.cursor_pos, injection.range.s_row, c_table.indents)
	else
		buffer.set_child_cur(c_table.win, injection.cursor_pos, injection.range.s_row)
	end

	---@type NJLspStatus?
	local lsp_status
	lsp_status, err = buffer.start_lsp(injection.pair.inj_lang, root_dir)
	if not lsp_status then
		if cfg.debug then
			vim.notify("ninjection.edit() warning: starting LSP " .. err, vim.log.levels.WARN)
			-- Don't return early on LSP failure
		end
	end

	-- Track parent, child buffer relations, in the event multiple child buffers
	-- are opened for the same injected content.
	-- Retrieve the existing ninjection table or initialize a new one
	---@type NJParent
	local p_ninjection
	ok, result = pcall(function()
		return vim.api.nvim_buf_get_var(p_bufnr, "ninjection")
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
		return vim.api.nvim_buf_set_var(p_bufnr, "ninjection", p_ninjection)
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
	---@type boolean, unknown, string?, integer?
	local ok, raw_output, err, this_bufnr

	ok, raw_output = pcall(function()
		return vim.api.nvim_get_current_buf()
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	if type(raw_output) ~= "number" then
		error(
			"ninjection.replace() error: Could not retrieve a buffer handle "
				.. "calling vim.api.nvim_get_current_buf().",
			2
		)
	end
	this_bufnr = raw_output
	---@cast this_bufnr integer

	-- We need to validate that this buffer has a parent buffer, and that the
	-- parent buffer has this buffer as a child.
	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_var(this_bufnr, "ninjection")
	end)
	if not ok or type(raw_output) ~= "table" then
		err = tostring(raw_output)
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
	local nj_child_b = raw_output
	if not nj_child_b.p_bufnr then
		error("ninjection.replace() error: Could not retrieve valid parent buffer for this buffer.", 2)
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_var(nj_child_b.p_bufnr, "ninjection")
	end)
	if not ok or type(raw_output) ~= "table" then
		err = tostring(raw_output)
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
	local nj_p_b = raw_output
	if not vim.tbl_contains(nj_p_b.children, this_bufnr) then
		error("ninjection.replace() error: The recorded parent buffer has no record of this buffer.", 2)
	end
	---@cast nj_p_b NJParent

	ok, raw_output = pcall(function()
		return vim.api.nvim_win_get_cursor(0)
	end)
	if not ok or type(raw_output) ~= "table" then
		error(tostring(raw_output), 2)
	end
	---@type integer[]
	local this_cursor = raw_output
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

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_lines(0, 0, -1, false)
	end)
	if not ok or type(raw_output) ~= "table" then
		error(tostring(raw_output), 2)
	end
	---@type string[]
	local rep_text = raw_output
	if not rep_text or rep_text == "" then
		if cfg.debug then
			vim.notify(
				"ninjection.replace() warning: No replacement text returned " .. "by vim.api.nvim_buf_get_lines()",
				vim.log.levels.WARN
			)
		end
		return nil
	end

	if cfg.preserve_indents then
		raw_output, err = buffer.restore_indents(rep_text, nj_child_b.p_indents)
		if not raw_output or type(raw_output) ~= "table" then
			if cfg.debug then
				vim.notify(
					"ninjection.replace() warning: buffer.restore_indents() could not restore indents: " .. err,
					vim.log.levels.WARN
				)
			end
		else
			rep_text = raw_output
		end
	end

	vim.notify(vim.inspect(nj_child_b))

	ok, raw_output = pcall(function()
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
		error(tostring(raw_output), 2)
	end

	ok, raw_output = pcall(function()
		return vim.cmd("bdelete!")
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end

	-- Remove the child entry in the parent after deleting the buffer
	nj_p_b.children[this_bufnr] = nil
	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_set_var(nj_child_b.p_bufnr, "ninjection", nj_p_b)
	end)
	if not ok then
		err = tostring(raw_output)
		if cfg.debug then
			vim.notify(
				"ninjection.replace() warning: could not remove child buffer "
					.. "entry from parent buffer after deleting buffer."
					.. err,
				vim.log.levels.WARN
			)
		end
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_set_current_buf(nj_child_b.p_bufnr)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end

	-- Reset the cursor to the same relative position in the parent buffer
	---@type integer[]
	local pos
	if cfg.preserve_indents then
		pos = {
			this_cursor[1] + nj_child_b.p_range.s_row + 1,
			this_cursor[2] + nj_child_b.p_indents.l_indent,
		}
	else
		pos = { this_cursor[1] + nj_child_b.p_range.s_row, this_cursor[2] }
	end

	ok, raw_output = pcall(function()
		return vim.api.nvim_win_set_cursor(0, pos)
	end)
	if not ok then
		err = tostring(raw_output)
		if cfg.debug then
			vim.notify(
				"ninjection.replace() warning: could not restore cursor position in the parent buffer." .. err,
				vim.log.levels.WARN
			)
		end
	end
end

return ninjection
