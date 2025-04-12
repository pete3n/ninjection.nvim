---@module "ninjection.buffer"
---@brief
--- The buffer module contains helper functions utilized by the main ninjection
--- module for creating and editing injected text in buffers.
---
local M = {}
---@nodoc
---@type Ninjection.Config
local cfg = require("ninjection.config").values
local lspconfig = require("lspconfig")

-- We need to provide a way of recording and restoring whitespace from the parent
-- buffer to allow easily formatting the buffer without worrying about its
-- relative placement in the parent buffer.

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
	---@type boolean, unknown, string[]
	local ok, raw_output, lines

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	if type(raw_output) ~= "table" then
		error("ninjection error: Expected vim.api.nvim_buf_get_lines() to return a table.", 2)
	end
	---@cast raw_output string[]
	lines = raw_output

	if #lines == 0 then
		if cfg.debug then
			vim.notify(
				"ninjection.buffer.get_indents() warning: No lines returned "
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
	---@type boolean, unknown, string[]?
	local ok, raw_output, lines

	if type(text) == "string" then
		ok, raw_output = pcall(function()
			return vim.split(text, "\n")
		end)
		if not ok then
			error(tostring(raw_output), 2)
		end
		if type(raw_output) ~= "table" then
			error("ninjection error: Expected a table returned from vim.split()", 2)
		end
		---@cast raw_output string[]
		lines = raw_output
		if #lines == 0 then
			if cfg.debug then
				vim.notify(
					"ninjection.buffer.restore_indents() warning: No lines " .. "returned from calling vim.split()",
					vim.log.levels.WARN
				)
			end
			return nil
		end
	elseif type(text) == "table" then
		lines = text
	else
		error("ninjection.buffer.restore_indents() error: Text must be a string or " .. "a table of lines", 2)
	end
	---@cast lines string[]

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

---@nodoc
--- Opens a vertically or horizontally split window for the child buffer.
---@param split_cmd string v_split or split.
---@param bufnr integer child bufnr.
---@return integer winid Handle for new window.
local function open_split_win(split_cmd, bufnr)
	---@type boolean, unknown, integer|nil
	local ok, raw_output, winid
	vim.cmd(split_cmd)
	ok, winid = pcall(vim.api.nvim_get_current_win)
	if not ok or not winid then
		error(
			"ninjection error: vim.api.nvim_get_current_win() did not return a " .. " window handle." .. tostring(winid),
			2
		)
	end
	ok, raw_output = pcall(function()
		return vim.api.nvim_win_set_buf(winid, bufnr)
	end)
	if not ok then
		error(
			"ninjection error: vim.api.nvim_win_set_buf() failed to set buffer "
				.. "in new window: "
				.. tostring(raw_output),
			2
		)
	end
	---@cast winid integer
	return winid
end

---@nodoc
--- Creates a window for the provided child buffer with either floating, v_split
--- or h_split styles.
---@param bufnr integer The buffer to create a viewport for.
---@param style EditorStyle The window style to edit the buffer with.
---@return integer winid Default: 0 (cur_win), child window handle, if created.
local function create_child_win(bufnr, style)
	---@type boolean, unknown, integer
	local ok, raw_output, winid

	if style == "floating" then
		ok, raw_output = pcall(function()
			return vim.api.nvim_open_win(bufnr, true, cfg.win_config)
		end)
		if not ok then
			error(tostring(raw_output), 2)
		end
		if type(raw_output) ~= "number" then
			error("ninjection error: vim.api.nvim_open_win() did not return a window " .. "handle.")
		end
		---@cast raw_output integer
		winid = raw_output
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

---@tag ninjection.buffer.create_child()
---@brief
--- Creates a child buffer to edit injected language text.
---
--- Parameters ~
---@param p_bufnr integer - Buffer handle for parent buffer.
---@param p_name string - Name for parent buffer.
---@param p_range NJRange - Text range for the injected text.
---@param root_dir string - Root directory for project, or cwd.
---@param text string - Text to populate the child buffer with.
---@param lang string - Language to configure buffer for.
---
---@return { bufnr: integer?, win: integer?, indents: NJIndents } c_table, string? err
-- Returns table containing handles for the child buffer and window, if
-- available, and parent indents.
--
M.create_child = function(p_bufnr, p_name, p_range, root_dir, text, lang)
	---@type boolean, unknown, string?, integer?
	local ok, raw_output, err, c_bufnr

	ok, raw_output = pcall(function()
		return vim.fn.setreg(cfg.register, text)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	vim.notify("ninjection.edit(): Copied injected content text to register: " .. cfg.register, vim.log.levels.INFO)

	---@type integer?
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
	---@type NJIndents?
	local p_indents
	if cfg.preserve_indents then
		p_indents, err = M.get_indents(0)
		if not p_indents then
			if cfg.debug then
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
			if cfg.debug then
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

---@tag ninjection.buffer.set_child_cur()
---@brief
--- Sets the child cursor to the same relative position as in the parent window.
---
--- Parameters ~
---@param c_win integer Handle for child window to set the cursor in.
---@param p_cursor integer[] Parent cursor pos.
---@param s_row integer Starting row from the parent to offset the child cursor by.
---@param indents NJIndents? Indents to calculate additional offsets with.
---
---@return string? err
---
M.set_child_cur = function(c_win, p_cursor, s_row, indents)
	---@type boolean, unknown, string?
	local ok, raw_output, err
	---@type integer[]?
	local offset_cur
	-- Assuming autoformat will remove any existing indents, we need to offset
	-- the cursor for the removed indents.
	if cfg.preserve_indents and cfg.auto_format then
		---@type integer
		local relative_row = p_cursor[1] - s_row
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
		if cfg.debug then
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

---@tag ninjection.buffer.start_lsp()
---@brief
--- Starts an appropriate LSP for the provided language.
---
--- Parameters ~
---@param lang string - The filetype of the injected language (e.g., "lua", "python").
---@param root_dir string - The root directory for the buffer.
---
---@return NJLspStatus? result, string? err - The LSP status.
---
M.start_lsp = function(lang, root_dir)
	---@type boolean, unknown, string?
	local ok, raw_output, lang_lsp

	-- The injected language must be mapped to an LSP
	lang_lsp = cfg.lsp_map[lang]
	if not lang_lsp then
		vim.notify(
			"ninjection.buffer.start_lsp() warning: No LSP mapped to "
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
		return lspconfig[lang_lsp].config_def.default_config
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	---@type table?
	local lsp_def = raw_output
	if not lsp_def then
		vim.notify(
			"ninjection.buffer.start_lsp() warning: Could not find "
				.. "default_config for "
				.. lang_lsp
				.. ". Ensure it is installed and "
				.. "properly configured for lspconfig.",
			vim.log.levels.WARN
		)
		return { "unconfigured", -1 }
	end
	---@cast lsp_def table

	-- The LSP binary path must exist
	-- RPC function support is not implemented
	---@type string[]|fun(dispatchers: vim.lsp.rpc.Dispatchers): vim.lsp.rpc.PublicClient?
	local lsp_cmd = lsp_def.cmd
	if not lsp_cmd or #lsp_cmd == 0 then
		vim.notify(
			"ninjection.buffer.start_lsp() warning: Command to execute "
				.. lang_lsp
				.. " does not exist. Ensure it is installed and configured."
				.. vim.log.levels.WARN
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
			"ninjection.buffer.start_lsp() warning: The LSP command: " .. lsp_cmd[1] .. " is not executable.",
			vim.log.levels.WARN
		)
		return { "no-exec", -1 }
	end

	-- The LSP must support our injected language
	if not vim.tbl_contains(lsp_def.filetypes, lang) then
		vim.notify(
			"ninjection.buffer.start_lsp() warning: The configured LSP: "
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
	---@type integer?
	local client_id = raw_output
	if client_id == nil then
		vim.notify(
			"ninjection.buffer.start_lsp() warning: The LSP: "
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
