---@module "ninjection.buffer"
---@brief
--- The buffer module contains helper functions utilized by the main ninjection
--- module for creating and editing injected text in buffers.
---
local M = {}
---@nodoc
---@type Ninjection.Config
local cfg = require("ninjection.config").values
local has_lspconfig, lspconfig = pcall(require, "lspconfig")
if not has_lspconfig then
	vim.notify("ninjection.nvim requires 'lspconfig' plugin for LSP features", vim.log.levels.ERROR)
	return
end

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
---@param child NJChild - Buffer child object.
---@param text string - Text to populate the child buffer with.
---
---@return { bufnr: integer?, win: integer?, indents: NJIndents } c_table, string? err
-- Returns table containing handles for the child buffer and window, if
-- available, and parent indents.
--
M.create_child = function(child, text)
	---@type boolean, unknown, string?
	local ok, result, err

	ok, result = pcall(function()
		return vim.fn.setreg(cfg.register, text)
	end)
	if not ok then
		error(tostring(result), 2)
	end
	vim.notify("ninjection.edit(): Copied injected content text to register: " .. cfg.register, vim.log.levels.INFO)

	---@type integer
	local c_bufnr = vim.api.nvim_create_buf(true, true)
	if not c_bufnr then
		error("ninjection.edit() error: Failed to create a child buffer.", 2)
	end

	---@type integer
	local c_win = create_child_win(c_bufnr, cfg.editor_style)

	ok, result = pcall(function()
		return vim.api.nvim_set_current_buf(c_bufnr)
	end)
	if not ok then
		error(tostring(result), 2)
	end

	ok, result = pcall(function()
		return vim.cmd('normal! "zp')
	end)
	if not ok then
		error(tostring(result), 2)
	end

	ok, result = pcall(function()
		return vim.cmd("file " .. child.p_name .. ":" .. child.ft .. ":" .. c_bufnr)
	end)
	if not ok then
		error(tostring(result), 2)
	end

	ok, result = pcall(function()
		return vim.cmd("set filetype=" .. child.ft)
	end)
	if not ok then
		error(tostring(result), 2)
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
		p_indents = { t_indent = 0, b_indent = 0, l_indent = 0, tab_indent = 0 }
		---@cast p_indents NJIndents
	end
	child.p_indents = p_indents

	ok, result = pcall(function()
		return vim.cmd("doautocmd FileType " .. child.ft)
	end)
	if not ok then
		error(tostring(result), 2)
	end

	if cfg.auto_format then
		ok, result = pcall(function()
			return vim.cmd("lua " .. cfg.format_cmd)
		end)
		if not ok then
			if cfg.debug then
				err = tostring(result)
				vim.notify(
					'ninjection.edit() warning: Calling vim.cmd("lua "' .. cfg.format_cmd .. ")\n" .. err,
					vim.log.levels.WARN
				)
				-- Don't return early on auto-format error
			end
		end
	end

	-- Save the child information to the buffer's ninjection table
	ok, result = pcall(function()
		return vim.api.nvim_buf_set_var(c_bufnr, "ninjection", child)
	end)
	if not ok then
		error(tostring(result), 2)
	end

	return { bufnr = c_bufnr, win = c_win, indents = p_indents }
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

---@tag NJLspStatus
---@class NJLspStatus
---@brief Store LSP status and associated client ID.
---
---@field status string - The LSP startup status. Possible values: `"unmapped"`,
--- `"unconfigured"`, `"unavailable"`, `"no-exec"`, `"unsupported"`, `"failed_start"`,
--- `"started"`
---@field client_id integer? - The client ID of the started LSP, -1 on failure
local NJLspStatus = {}
NJLspStatus.__index = NJLspStatus

--- Check if the client is attached to the given buffer and initialized
---@param bufnr integer
---@return boolean
function NJLspStatus:is_attached(bufnr)
	if self.status ~= "started" or not self.client_id then
		return false
	end

	local client = vim.lsp.get_client_by_id(self.client_id)
	if not client or not client.initialized then
		return false
	end

	return client.attached_buffers and client.attached_buffers[bufnr] == true
end

function NJLspStatus.new(status, client_id)
	return setmetatable({
		status = status,
		client_id = client_id or -1,
	}, NJLspStatus)
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
---@param bufnr integer - The bufnr handle to attach the LSP to.
---
---@return NJLspStatus? result, string? err - The LSP status.
---
M.start_lsp = function(lang, root_dir, bufnr)
	-- The injected language must be mapped to an LSP
	---@type string?, string?
	local lang_lsp = cfg.lsp_map[lang]
	local err
	if not lang_lsp then
		err = "ninjection.buffer.start_lsp() warning: No LSP mapped to "
			.. "language: "
			.. lang
			.. " check your configuration."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN, { title = "Ninjection debug" })
		end
		return NJLspStatus.new("unmapped", nil), err
	end
	---@cast lang_lsp string

	-- The LSP must have an available configuration
	---@type boolean, lspconfig.Config?
	local ok, lsp_def = pcall(function()
		return lspconfig[lang_lsp]
	end)
	if not ok or not lsp_def then
		err = "Ninjection.buffer.start_lsp() error: no LSP configuration for: " .. lang_lsp .. " " .. tostring(lsp_def)
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN, { title = "Ninjection warning" })
		end
		return NJLspStatus.new("unconfigured", nil), err
	end
	---@cast lsp_def lspconfig.Config

	-- The LSP binary path must exist
	-- RPC function support is not implemented
	---@type string[]|fun(dispatchers: vim.lsp.rpc.Dispatchers): vim.lsp.rpc.PublicClient?
	local lsp_cmd = lsp_def.cmd
	if not lsp_cmd or #lsp_cmd == 0 then
		err = "ninjection.buffer.start_lsp() warning: Command to execute "
			.. lang_lsp
			.. " does not exist. Ensure it is installed and configured."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN, { title = "Ninjection warning" })
		end
		return NJLspStatus.new("unavailable", nil), err
	end
	---@cast lsp_cmd string[]

	-- The LSP binary path must be executable
	-- The command must be the first element
	---@type unknown?
	local is_executable
	ok, is_executable = pcall(function()
		return vim.fn.executable(lsp_cmd[1])
	end)
	if not ok or is_executable ~= 1 then
		err = "ninjection.buffer.start_lsp() warning: The LSP command: "
			.. lsp_cmd[1]
			.. " is not executable. "
			.. tostring(is_executable)
		vim.notify(err, vim.log.levels.WARN, { title = "Ninjection warning" })
		return NJLspStatus.new("no-exec", nil), err
	end
	---@cast is_executable integer

	-- The LSP must support our injected language
	if not vim.tbl_contains(lsp_def.filetypes, lang) then
		err = "ninjection.buffer.start_lsp() warning: The configured LSP: "
			.. lang_lsp
			.. " does not support "
			.. lang
			.. " modify your configuration "
			.. " to use an appropriate LSP."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN, { title = "Ninjection warning" })
		end
		return NJLspStatus.new("unsupported", nil), err
	end

	---@type integer?
	local client_id = vim.lsp.start({
		name = lang_lsp,
		cmd = lsp_cmd,
		root_dir = root_dir,
	})

	-- Attach explicitly to the buffer
	if client_id then
		vim.lsp.buf_attach_client(bufnr, client_id)
	else
		err = "ninjection.buffer.start_lsp() warning: The LSP: "
			.. lang_lsp
			.. " did not return a client_id, check your language client logs "
			.. "(default ~/.local/state/nvim/lsp.log) for more information."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN, { title = "Ninjection warning" })
		end
		return NJLspStatus.new("failed_start", nil), err
	end
	---@cast client_id integer

	vim.defer_fn(function()
		vim.notify(vim.inspect(vim.lsp.get_clients({ bufnr = bufnr })), vim.log.levels.INFO)
	end, 500)

	return NJLspStatus.new("started", client_id), nil
end

return M
