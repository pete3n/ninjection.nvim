---@module "ninjection.util"

local M = {}
local cfg = require("ninjection.config").cfg
local lspconfig = require("lspconfig")

-- We need to provide a way of recording and restoring whitespace from the parent
-- buffer to allow easily formatting the buffer without worrying about its
-- relative placement in the parent buffer.

---Function: Find whitespace indents (top, bottom, left) in the provided buffer.
---@param bufnr integer  Buffer handle
---@return NJIndents|nil table Stores indentation values
---@return nil|string err Error string, if applicable
--- Return, on success, A table containing:
---  - t_indent: number of blank lines at the top.
---  - b_indent: number of blank lines at the bottom.
---  - l_indent: minimum number of leading spaces on nonempty lines.
--- Return, on failure, nil and error string, if applicable
M.get_indents = function(bufnr)
	---@type boolean, any|nil, string[]|nil
	local ok, raw_output, lines

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	lines = raw_output
	if not lines or #lines == 0 then
		if cfg.suppress_warnings == false then
			vim.notify(
				"ninjection.util.get_indents() warning: No lines returned "
					.. "from calling vim.api.nvim_buf_get_lines()",
				vim.log.levels.WARN
			)
		end
	end
	---@cast lines string[]

	---@type NJIndents
	local indents = { t_indent = 0, b_indent = 0, l_indent = math.huge }

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
			---@type string|nil
			local indent = line:match("^(%s*)")
			if indent then
				-- Use vim.fn.strdisplaywidth() to calculate the visible width of the indent,
				-- which will account for tabs.
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

	return indents, nil
end

--- Restores the recorded whitespace indents (top, bottom, and left indent)
--- to a block of text.
---
--- @param text string|table<integer, string> The text to restore indents in.
--- Can be either a string (with newline separators) or a table of lines.
--- @param indents NJIndents Table with indent values for t, b, l
--- @return table<integer, string>|nil restored_lines A table of lines with
--- the indents restored.
--- @return nil|string err  Error message, if applicable
M.restore_indents = function(text, indents)
	---@type boolean, any|nil, table<integer, string>|nil
	local ok, raw_output, lines

	if type(text) == "string" then
		ok, raw_output = pcall(function()
			return vim.split(text, "\n")
		end)
		if not ok then
			error(tostring(raw_output), 2)
		end
		lines = raw_output
		if not lines then
			if cfg.suppress_warnings == false then
				vim.notify(
					"ninjection.util.restore_indents() warning: No lines " .. "returned from calling vim.split()",
					vim.log.levels.WARN
				)
			end
			return nil
		end
	elseif type(text) == "table" then
		lines = text
	else
		error("ninjection.util.restore_indents() error: Text must be a string or " .. "a table of lines", 2)
	end
	---@cast lines table<integer, string>

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
			local tab_size = vim.o.tabstop or 8
			-- Ensure the resulting indent length is not negative.
			local adjusted_indent = string.rep(" ", math.max(0, (indents.l_indent or 0) - tab_size))
			table.insert(lines, adjusted_indent)
		else
			table.insert(lines, "")
		end
	end

	return lines
end

-- Function: Open a vertical or horizontal split window for the child buffer.
---@param split_cmd string vsplit or split.
---@param bufnr integer child bufnr.
---@return integer|nil winid Handle for new window.
local function open_split_win(split_cmd, bufnr)
	---@type boolean, any|nil, integer|nil
	local ok, raw_output, winid
	vim.cmd(split_cmd)
	ok, winid = pcall(vim.api.nvim_get_current_win)
	if not ok or not winid then
		error("create_child_win() error: no handle returned for window: " .. tostring(winid), 2)
	end
	ok, raw_output = pcall(function()
		return vim.api.nvim_win_set_buf(winid, bufnr)
	end)
	if not ok then
		error("create_child_win() error: failed to set buffer in new window: " .. tostring(raw_output), 2)
	end
	---@cast winid integer
	return winid
end

-- Function: Set the child window cursor to the same relative position as it was
-- in the parent.
---@param bufnr integer The buffer to create a viewport for.
---@param style EditorStyle The window style to edit the buffer with.
---@return integer winid Default: 0, child window handle, if created.
local function create_child_win(bufnr, style)
	---@type boolean, any|nil, integer|nil
	local ok, raw_output, winid

	if style == "floating" then
		---@type number, number, number, number
		local width = math.floor(vim.o.columns * 0.8)
		local height = math.floor(vim.o.lines * 0.8)
		local row = math.floor((vim.o.lines - height) / 2)
		local col = math.floor((vim.o.columns - width) / 2)

		---@type table
		local opts = {
			style = "minimal",
			relative = "editor", -- relative to the whole editor
			width = width,
			height = height,
			row = row,
			col = col,
			border = "single",
		}

		ok, raw_output = pcall(function()
			return vim.api.nvim_open_win(bufnr, true, opts)
		end)
		if not ok then
			error(tostring(raw_output), 2)
		end
		---@type integer|nil
		winid = raw_output
		if not winid then
			error("create_child_win() error: no handle returned for window: " .. tostring(raw_output), 2)
		end
		---@cast winid integer
		return winid
	elseif style == "v_split" then
		winid = open_split_win("vsplit", bufnr)
		---@cast winid integer
		return winid
	elseif style == "h_split" then
		winid = open_split_win("split", bufnr)
		---@cast winid integer
		return winid
	end

	-- Default return of cur_win
	return 0
end

-- Function: Create a child buffer and window to edit injected language text.
---@param p_bufnr integer Buffer handle for parent buffer.
---@param p_name string Name for parent buffer.
---@param p_range NJRange Text range for the injected text.
---@param root_dir string Root directory for project, or cwd.
---@param text string Text to populate the child buffer with.
---@param lang string Language to configure buffer for.
---@return {bufnr: integer|nil, win: integer|nil, indents: NJIndents} c_table
-- containing handles for the child buffer and window, if available, and parent
-- indents.
---@return string|nil err Error string, if applicable.
M.create_child_buf = function(p_bufnr, p_name, p_range, root_dir, text, lang)
	---@type boolean, any|nil, string|nil, integer|nil
	local ok, raw_output, err, c_bufnr

	ok, raw_output = pcall(function()
		return vim.fn.setreg(cfg.register, text)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	vim.notify("ninjection.edit(): Copied injected content text to register: " .. cfg.register, vim.log.levels.INFO)

	---@type integer|nil
	c_bufnr = vim.api.nvim_create_buf(true, true)
	if not c_bufnr then
		error("ninjection.edit() error: Failed to create a child buffer.", 2)
	end
	---@cast c_bufnr integer

	---@type integer
	local c_win = create_child_win(c_bufnr, cfg.editor_style)

	ok, raw_output = pcall(function()
		return vim.api.nvim_set_current_buf(c_bufnr)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end

	ok, raw_output = pcall(function()
		return vim.cmd('normal! "zp')
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end

	ok, raw_output = pcall(function()
		return vim.cmd("file " .. p_name .. ":" .. lang .. ":" .. c_bufnr)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end

	ok, raw_output = pcall(function()
		return vim.cmd("set filetype=" .. lang)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end

	-- Preserve indentation after creating and pasting buffer contents, before
	-- autoformatting, or they will be lost.
	---@type NJIndents|nil
	local p_indents
	if cfg.preserve_indents then
		p_indents, err = M.get_indents(0)
		if not p_indents then
			if not cfg.suppress_warnings then
				vim.notify(
					"ninjection.edit() warning: Unable to preserve indentation "
						.. "with get_indents(): "
						.. tostring(err),
					vim.log.levels.WARN
				)
			end
			-- Don't return early on indentation errors
		end
		---@cast p_indents NJIndents
	end
	-- Initialized to 0 if unset
	if not p_indents then
		p_indents = { t_indent = 0, b_indent = 0, l_indent = 0 }
		---@cast p_indents NJIndents
	end

	ok, raw_output = pcall(function()
		return vim.cmd("doautocmd FileType " .. lang)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end

	if cfg.auto_format then
		ok, raw_output = pcall(function()
			return vim.cmd("lua " .. cfg.format_cmd)
		end)
		if not ok then
			if not cfg.suppress_warnings then
				err = tostring(raw_output)
				vim.notify(
					'ninjection.edit() warning: Calling vim.cmd("lua "' .. cfg.format_cmd .. ")\n" .. err,
					vim.log.levels.WARN
				)
				-- Don't return early on auto-format error
			end
		end
	end

	---@type NJChild
	local child_ninjection = {
		bufnr = c_bufnr,
		root_dir = root_dir,
		p_bufnr = p_bufnr,
		p_indents = p_indents,
		p_range = p_range,
	}

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_set_var(c_bufnr, "ninjection", child_ninjection)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end

	return { bufnr = c_bufnr, win = c_win, indents = p_indents }
end

-- Function: Set the child cursor to the same relative position as in the
-- parent window.
---@param c_win integer Handle for child window to set the cursor in.
---@param p_cursor integer[] Parent cursor pos.
---@param s_row integer Starting row from the parent to offset the child cursor by.
---@param indents NJIndents? Indents to calculate additional offsets with.
---@return nil|string err Error string, if applicable.
M.set_child_cur = function(c_win, p_cursor, s_row, indents)
	---@type boolean, any|nil, string|nil
	local ok, raw_output, err
	---@type integer[]|nil
	local offset_cur
	-- Assuming autoformat will remove any existing indents, we need to offset
	-- the cursor for the removed indents.
	if cfg.preserve_indents and cfg.auto_format then
		---@type integer
		local relative_row = p_cursor[1] - (s_row + cfg.injected_comment_lines)
		relative_row = math.max(1, relative_row)
		---@type integer
		if indents then
			local relative_col = p_cursor[2] - indents.l_indent
			relative_col = math.max(0, relative_col)
			offset_cur = { relative_row, relative_col }
		end
	else
		---@type integer
		local relative_row = p_cursor[1] - s_row
		relative_row = math.max(1, relative_row)
		offset_cur = { relative_row, p_cursor[2] }
	end
	---@cast offset_cur integer[]

	ok, raw_output = pcall(function()
		return vim.api.nvim_win_set_cursor(c_win, offset_cur)
	end)
	if not ok then
		if not cfg.suppress_warnings then
			err = tostring(raw_output)
			vim.notify(
				"ninjection.edit() warning: Calling vim.api.nvim_win_set_cursor"
					.. "(0, "
					.. tostring(offset_cur)
					.. "\n"
					.. err,
				vim.log.levels.WARN
			)
		end
	end

	return nil
end

-- Autocommands don't trigger properly when creating and arbitrarily assigning
-- filetypes to buffers, so we need a function to start the appropriate LSP.

--- Start an appropriate LSP for the provided language
--- @param lang string The filetype of the injected language (e.g., "lua", "python").
--- @param root_dir string The root directory for the buffer.
--- @return NJLspStatus|nil result  A table containing the LSP status and client_id
--- Return: "unmapped", "unconfigured", "unavailable", "no-exec", "unsupported",
--- "failed_start", "started" and client_id if available
--- @return nil|string err Error message, if applicable
M.start_lsp = function(lang, root_dir)
	---@type boolean, any|nil, string|nil, string|nil
	local ok, raw_output, lang_lsp

	-- The injected langauge must be mapped to an LSP value
	lang_lsp = cfg.lsp_map[lang]
	if not lang_lsp then
		vim.notify(
			"ninjection.util.start_lsp() warning: No LSP mapped to "
				.. "language: "
				.. lang
				.. " check your configuration.",
			vim.log.levels.WARN
		)
		return { "unmapped", -1 }
	end
	---@cast lang_lsp string

	-- The LSP must have an available configuration
	ok, raw_output = pcall(function()
		return lspconfig[lang_lsp]
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	---@type lspconfig.Config|nil
	local lsp_def = raw_output
	if not lsp_def then
		vim.notify(
			"ninjection.util.start_lsp() warning: Could not find "
				.. "default_config for "
				.. lang_lsp
				.. ". Ensure it is installed and "
				.. "properly configured for lspconfig.",
			vim.log.levels.WARN
		)
		return { "unconfigured", -1 }
	end
	---@cast lsp_def lspconfig.Config

	-- The LSP binary path must exist
	-- RPC function support is not implemented
	---@type string[]|fun(dispatchers: vim.lsp.rpc.Dispatchers): vim.lsp.rpc.PublicClient|nil
	local lsp_cmd = lsp_def.cmd
	if not lsp_cmd or #lsp_cmd == 0 then
		vim.notify(
			"ninjection.util.start_lsp() warning: Command to execute "
				.. lang_lsp
				.. " does not exist. Ensure it is installed and configured.",
			vim.log.levels.WARN
		)
		return { "unavailable", -1 }
	end
	---@cast lsp_cmd string[]

	-- The LSP binary path must be executable
	-- The command must be the first element
	ok, raw_output = pcall(function()
		return vim.fn.executable(lsp_cmd[1])
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	if raw_output ~= 1 then
		vim.notify(
			"ninjection.util.start_lsp() warning: The LSP command: " .. lsp_cmd[1] .. " is not executable.",
			vim.log.levels.WARN
		)
		return { "no-exec", -1 }
	end

	-- The LSP must support our injected language
	if not vim.tbl_contains(lsp_def.filetypes, lang) then
		vim.notify(
			"ninjection.util.start_lsp() warning: The configured LSP: "
				.. lang_lsp
				.. " does not support "
				.. lang
				.. " modify your configuration "
				.. " to use an appropriate LSP.",
			vim.log.levels.WARN
		)
		return { "unsupported", -1 }
	end

	ok, raw_output = pcall(function()
		return vim.lsp.start({
			name = lang_lsp,
			cmd = lsp_cmd,
			root_dir = root_dir,
		})
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	---@type integer|nil
	local client_id = raw_output
	if client_id == nil then
		vim.notify(
			"ninjection.util.start_lsp() warning: The LSP: "
				.. lang_lsp
				.. " did not return a client_id, check your language client logs "
				.. "(default ~/.local/state/nvim/lsp.log) for more information.",
			vim.log.levels.WARN
		)
		return { "failed_start", -1 }
	end
	---@cast client_id integer

	return { "started", client_id }
end

return M
