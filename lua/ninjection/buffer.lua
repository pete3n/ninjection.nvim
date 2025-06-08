---@module "ninjection.buffer"
---@brief
--- The buffer module contains helper functions utilized by the main ninjection
--- module for creating and editing injected text in buffers.
---
local M = {}
---@nodoc
---@type Ninjection.Config
local cfg = require("ninjection.config").values
local Parent = require("ninjection.parent")

---@nodoc
--- Opens a vertically or horizontally split window for the child buffer.
---@param split_cmd string v_split or split.
---@param bufnr integer child bufnr.
---@return integer win_id, string? err
--- Handle for new window or 0 on failure.
local function open_split_win(split_cmd, bufnr)
	---@type string?
	local err
	---@type boolean
	local split_ok = pcall(function()
		return vim.cmd(split_cmd)
	end)
	if not split_ok then
		err = "ninjection.buffer.open_split_win() error: Window split cmd failed ... " .. split_cmd
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return 0, err
	end

	---@type boolean, integer
	local win_ok, win_id
	win_ok, win_id = pcall(vim.api.nvim_get_current_win)
	if not win_ok or win_id == 0 then
		err = "ninjection.buffer.open_split_win() error: Failed to open child window."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return 0, err
	end

	---@type boolean
	local buf_ok = pcall(function()
		return vim.api.nvim_win_set_buf(win_id, bufnr)
	end)
	if not buf_ok then
		err = "ninjection.buffer.open_split_win() error: Failed to set window buffer."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return 0, err
	end

	return win_id, nil
end

---@nodoc
--- Creates a window for the provided child buffer with either floating, v_split
--- or h_split styles.
---@param bufnr integer The buffer to create a viewport for.
---@param style EditorStyle The window style to edit the buffer with.
---@return integer win_id, string? err
--- Default: 0 (cur_win), child window handle, if created.
M.create_child_win = function(bufnr, style)
	---@type integer, string?
	local win_id, err
	if style == "floating" then
		---@type boolean
		local win_ok
		win_ok, win_id = pcall(function()
			return vim.api.nvim_open_win(bufnr, true, cfg.win_config)
		end)
		if not win_ok or win_id == 0 then
			err = "ninjection.buffer.create_child_win() error: Failed to open child window."
			if cfg.debug then
				vim.notify(err, vim.log.levels.ERROR)
			end
			return 0, err
		end
		return win_id, nil
	elseif style == "v_split" then
		win_id, err = open_split_win("vsplit", bufnr)
		return win_id, err
	elseif style == "h_split" then
		win_id, err = open_split_win("split", bufnr)
		return win_id, err
	end

	-- Default return of cur_win
	return 0, nil
end

-- Track parent, child buffer relations, in the event multiple child buffers
-- are opened for the same injected content.
-- Retrieve the existing ninjection table or initialize a new one
---@param p_bufnr integer
---@param c_bufnr integer
---@return boolean success, string? err
M.reg_child_buf = function(p_bufnr, c_bufnr)
	---@type NJParent
	local nj_parent = Parent.NJParent.new({ children = {} })

	if not vim.api.nvim_buf_is_valid(p_bufnr) then
		---@type string
		local err = "buffer.reg_child_buf() error: The buffer, " .. p_bufnr .. " is invalid."
		if cfg.debug then
			vim.notify(err, vim.log.level.ERROR)
		end
		return false, err
	end

	---@type boolean, NJParent?
	local get_nj_ok, get_nj_return = pcall(vim.api.nvim_buf_get_var, p_bufnr, "ninjection")

	--- If the buffer already has a ninjection table, then we want to update the
	--- table by appending new children to it.
	if get_nj_ok and get_nj_return and get_nj_return.type == "NJParent" then
		---@cast get_nj_return NJParent
		nj_parent = get_nj_return
	end

	--- Existing ninjection child buffers cannot also be parents (grandparents)
	if get_nj_ok and get_nj_return and get_nj_return.type == "NJChild" then
		---@type string
		local err = "buffer.reg_child_buf() error: The buffer, "
			.. p_bufnr
			.. " is a ninjection child buffer already. It cannot be a parent, "
			.. " gandparents are not supported."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return false, err
	end
	table.insert(nj_parent.children, c_bufnr)

	---@type boolean
	local svar_ok = pcall(vim.api.nvim_buf_set_var, p_bufnr, "ninjection", nj_parent)
	if not svar_ok then
		---@type string
		local err = "buffer.reg_child_buf() error: Failed to set ninjection table var in parent bufnr: " .. p_bufnr
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	return true, nil
end

---@param c_bufnr integer
---@return NJChild? nj_child, string? err
M.get_buf_child = function (c_bufnr)

	if not vim.api.nvim_buf_is_valid(c_bufnr) then
		---@type string
		local err = "buffer.reg_child_buf() error: The buffer, " .. c_bufnr .. " is invalid."
		if cfg.debug then
			vim.notify(err, vim.log.level.ERROR)
		end
		return nil, err
	end

	---@type boolean, NJChild?
	local get_cnj_ok, get_cnj_return = pcall(vim.api.nvim_buf_get_var, c_bufnr, "ninjection")
	-- Assuming that a vailed get_var call for ninjection on a valid bufnr means that
	-- the table doesn't exist.
	if not get_cnj_ok then
		---@type string
		local err = "ninjection.buffer.get_buf_parent() error: Error retrieving ninjection table for buffer " .. c_bufnr
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end

	if not get_cnj_return or type(get_cnj_return) ~= "table" or get_cnj_return.type ~= "NJChild" then
		---@type string
		local err = "ninjection.buffer.get_buf_parent() error: No child ninjection table for buffer: " .. c_bufnr
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end
	---@cast get_cnj_return NJChild
	---@type NJChild
	local nj_child = get_cnj_return

	return nj_child, nil
end


---@tag ninjection.buffer.get_root_dir()
---@brief
--- Provides a root directory for attaching an LSP to a buffer.
--- Tries to retrieve workspace folders first, then falls back to cwd.
---
---@return string? root_dir, string? err
--- Root directory for new buffer.
M.get_root_dir = function()
	-- Try getting the workspace folders list first
	---@type boolean, string[]?
	local wks_ok, folders = pcall(vim.lsp.buf.list_workspace_folders)
	if wks_ok and type(folders) == "table" and type(folders[1]) == "string" and folders[1] ~= "" then
		---@cast folders string[]
		return folders[1], nil
	end

	-- Fallback to the current working directory
	---@type boolean, string?
	local cwd_ok, cwd = pcall(vim.fn.getcwd)
	if cwd_ok and type(cwd) == "string" and cwd ~= "" then
		---@cast cwd string
		return cwd, nil
	end

	---@type string
	local err = "ninjection.init.get_root_dir() error: Could not determine root dir."
	if cfg.debug then
		vim.notify(err, vim.log.levels.ERROR)
	end

	return nil, err
end

---@tag ninjection.buffer.get_indents()
---@brief
--- Finds whitespace indents (top, bottom, left) in the provided buffer.
---
--- Parameters ~
---@param bufnr integer - Buffer handle.
---
---@return NJIndents? indents, string? err
--- Returns, on success, a table containing:
---  - `t_indent`: number of blank lines at the top.
---  - `b_indent`: number of blank lines at the bottom.
---  - `l_indent`: minimum number of leading spaces on nonempty lines.
---
M.get_indents = function(bufnr)
	---@type boolean, string[]?
	local line_ok, lines
	line_ok, lines = pcall(function()
		return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	end)
	if not line_ok or not lines or #lines == 0 then
		---@type string
		local err = "ninjection.buffer.get_indents() error: Unable to retrieve lines from bufnr " .. bufnr
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end
	---@cast lines string[]

	---@type NJIndents
	local indents = { t_indent = 0, b_indent = 0, l_indent = math.huge, tab_indent = 0 }

	for _, line in ipairs(lines) do
		---@cast line string
		if line:match("^%s*$") then
			indents.t_indent = indents.t_indent + 1
		else
			break
		end
	end

	for i = #lines, 1, -1 do
		---@cast i number
		if lines[i]:match("^%s*$") then
			indents.b_indent = indents.b_indent + 1
		else
			break
		end
	end

	for _, line in ipairs(lines) do
		---@cast line string
		if not line:match("^%s*$") then
			---@type string?
			local indent = line:match("^(%s*)")
			if indent then
				-- Use vim.fn.strdisplaywidth() to calculate the visible width of the indent,
				-- which will account for tabs.
				---@type integer
				local count = vim.fn.strdisplaywidth(indent)
				if count < indents.l_indent then
					indents.l_indent = count
				end
			end
		end
	end

	if indents.l_indent == math.huge then
		indents.l_indent = 0
	end

	-- Calculate the tab indentation
	---@type integer, integer
	local tabstop = vim.o.tabstop or 8
	local adjusted_indent = math.max(0, (indents and indents.l_indent or 0) - tabstop)
	indents.tab_indent = adjusted_indent

	return indents, nil
end

---@tag ninjection.buffer.restore_indents()
---@brief
--- Restores the recorded whitespace indents (top, bottom, and left indent)
--- for the provided text.
---
--- Parameters ~
---@param text string|table<integer,string> The text to restore indents to.
--- Can be either a string (with newline separators) or a table of lines.
---@param indents NJIndents Table with indent values for t, b, l
---
---@return string[]? restored_lines, string? err
--- Lines with the indents restored.
---
M.restore_indents = function(text, indents)
	---@type string[]?
	local lines
	if type(text) == "string" then
		---@type boolean
		local split_ok
		split_ok, lines = pcall(function()
			return vim.split(text, "\n")
		end)
		if not split_ok or not lines or #lines == 0 then
			---@type string err
			local err = "ninjection.buffer.restore_indents() error: Unable to split text lines."
			if cfg.debug then
				vim.notify(err, vim.log.levels.ERROR)
			end
			return nil, err
		end
		---@cast lines string[]
	elseif type(text) == "table" then
		lines = text
		---@cast lines string[]
	else
		local err = "ninjection.buffer.restore_indents() error: Text must be a string or a table of lines."
		---@type string err
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end

	-- Create the left indentation string.
	---@type string
	local l_indent = string.rep(" ", indents.l_indent or 0)

	-- Only apply the left indent to non-blank lines
	for i, line in ipairs(lines) do
		---@cast i number
		---@cast line string
		if line:match("%S") then
			lines[i] = l_indent .. line
		end
	end

	-- Prepend top indent lines.
	for _ = 1, (indents.t_indent or 0) do
		table.insert(lines, 1, "")
	end

	-- Append bottom indent lines.
	for _ = 1, (indents.b_indent or 0) do
		if cfg.preserve_indents then
			-- Compute the left indent string, subtracting one tab size.
			---@type integer
			local tab_size = vim.o.tabstop or 8
			-- Ensure the resulting indent length is not negative.
			---@type string
			local adjusted_indent = string.rep(" ", math.max(0, (indents.l_indent or 0) - tab_size))
			table.insert(lines, adjusted_indent)
		else
			table.insert(lines, "")
		end
	end

	return lines
end


---@class NJChildCursor -- Options to calculate child window cursor position
---@field win integer -- Child window handle
---@field p_cursor integer[] -- Parent window cursor coordinates
---@field s_row integer -- Starting row to calculate offset from
---@field indents? NJIndents -- Optional indent preservation object
---@field text_meta? table<string, boolean> -- Metadata for text modifications
---
---@tag ninjection.buffer.set_child_cur()
---@brief
--- Sets the child cursor to the same relative position as in the parent window.
---
--- Parameters ~
---
--- @param opts NJChildCursor
---
--- @return nil|string err
function M.set_child_cur(opts)
	---@type boolean, unknown, string?
	local ok, raw_output, err
	---@type integer[]?
	local offset_cur
	-- Assuming autoformat will remove any existing indents, we need to offset
	-- the cursor for the removed indents.
	if cfg.preserve_indents and cfg.auto_format then
		---@type integer
		local relative_row = opts.p_cursor[1] - opts.s_row
		relative_row = math.max(1, relative_row)
		---@type integer
		if opts.indents then
			local relative_col = opts.p_cursor[2] - opts.indents.l_indent
			relative_col = math.max(0, relative_col)
			offset_cur = { relative_row, relative_col }
		end
	else
		---@type integer
		local relative_row = opts.p_cursor[1] - opts.s_row
		relative_row = math.max(1, relative_row)
		offset_cur = { relative_row, opts.p_cursor[2] }
	end
	---@cast offset_cur integer[]

	ok, raw_output = pcall(function()
		return vim.api.nvim_win_set_cursor(opts.win, offset_cur)
	end)
	if not ok then
		if cfg.debug then
			err = tostring(raw_output)
			vim.notify(
				"ninjection.buffer.set_child_cur() warning: Calling vim.api.nvim_win_set_cursor"
					.. opts.win
					.. tostring(offset_cur)
					.. "\n"
					.. err,
				vim.log.levels.WARN
			)
		end
	end

	return nil
end

return M
