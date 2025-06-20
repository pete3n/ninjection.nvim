---@module "ninjection.child"
---@brief
--- The buffer module contains the ninjection child object class.
---

---@nodoc
---@type Ninjection.Config
local cfg = require("ninjection.config").values

---@tag NJChildCursor
---@class NJChildCursor -- Options to calculate child window cursor position
---@brief Ninjection child cursor object, stores cursor information to sync
--- relative positions between parent and child buffers.
---@field p_cursor integer[] -- Parent window cursor coordinates
---@field s_row integer -- Starting row to calculate offset from
---@field indents? NJIndents -- Optional indent preservation object
---@field text_meta? table<string, boolean> -- Metadata for text modifications

---@tag NJChild
---@class NJChild
---@brief Ninjection child object, stores child information and associated parent info.
---
---@field type "NJChild"
---@field c_ft string Filetype in use for the child
---@field c_root_dir string Root directory associated with the child
---@field c_bufnr integer? Child bufnr - once initialized
---@field c_win integer? Child window, if applicable - once initialized
---@field p_bufnr integer Parent bufnr the child belongs to
---@field p_ft string Parent filetype
---@field p_name string Parent buffer name
---@field p_range NJRange Parent text range the child is created from
---@field p_text_meta? table<string, boolean> Metadata for language specific
--- text modifications
---@field p_indents? NJIndents Parent indents if preserved
local NJChild = {}
NJChild.__index = NJChild

---@param opts {
---  c_ft: string,
---  c_root_dir: string,
---  p_bufnr: integer,
---  p_ft: string,
---  p_name: string,
---  p_range: NJRange,
---  p_text_meta?: table<string, boolean>,
---  p_indents?: NJIndents,
---  c_bufnr?: integer,
---  c_win?: integer }
---
---@return NJChild
function NJChild.new(opts)
	local self = setmetatable({
		c_ft = opts.c_ft,
		c_root_dir = opts.c_root_dir,
		p_bufnr = opts.p_bufnr,
		p_ft = opts.p_ft,
		p_name = opts.p_name,
		p_range = opts.p_range,
		p_text_meta = opts.p_text_meta,
		p_indents = opts.p_indents,
		c_bufnr = opts.c_bufnr,
		c_win = opts.c_win,
	}, NJChild)

	-- Bypass __newindex to set immutable type
	rawset(self, "type", "NJChild")

	return self
end

-- Make 'type' field immutable
function NJChild.__newindex(t, k, v)
	if k == "type" then
		error("Cannot modify field 'type' of NJChild")
	else
		rawset(t, k, v)
	end
end

---@param obj any
---@return boolean
function NJChild.is_child(obj)
	return type(obj) == "table" and obj.type and obj.type == "NJChild"
end

---@nodoc
--- Initialize a child buffer with provided text, optionally initialize a window for it.
---@param opts {
--- text: string,
--- create_win?: boolean }
---
---@return boolean init_success, string? err
function NJChild:init_buf(opts)
	---@type boolean, unknown
	local reg_ok, reg_return = pcall(vim.fn.setreg, cfg.register, opts.text)
	if not reg_ok then
		---@type string
		local err = "ninjection.child:init_buf() error: Failed to copy injection text into register "
			.. cfg.register
			.. tostring(reg_return)
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		-- Don't return early on failed setreg
	end

	---@type boolean, integer
	local cbuf_ok, c_bufnr = pcall(vim.api.nvim_create_buf, true, true)
	if not cbuf_ok or c_bufnr == 0 then
		---@type string
		local err = "ninjection.child:init_buf() error: Failed to create child buffer."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end
	self.c_bufnr = c_bufnr

	-- Create autocommand for cleanup in the event the child buffer is closed outside
	-- of ninjection functions.
	---@type integer
	local p_bufnr = self.p_bufnr

	for _, event in ipairs({ "BufDelete", "BufWipeout" }) do
		vim.api.nvim_create_autocmd(event, {
			buffer = c_bufnr,
			once = true,
			callback = function()
				local parent = require("ninjection.buffer").get_njparent(p_bufnr)
				if not parent then
					return
				end

				for i, bufnr in ipairs(parent.children or {}) do
					if bufnr == c_bufnr then
						table.remove(parent.children, i)
						parent:update_buf()
						if cfg.debug then
							vim.notify(
								"ninjection: autocmd cleaned up child bufnr " .. c_bufnr,
								vim.log.levels.DEBUG
							)
						end
						break
					end
				end
			end,
		})
	end

	if opts.create_win then
		---@type integer, string?
		local c_win, cwin_err
		c_win, cwin_err = require("ninjection.buffer").create_child_win(c_bufnr, cfg.editor_style)
		if not c_win or cwin_err then
			---@type string
			local err = "ninjection.child:init_buf() error: Failed to create child window... " .. tostring(cwin_err)
			if cfg.debug then
				vim.notify(err, vim.log.levels.ERROR)
			end
			return false, err
		end
		self.c_win = c_win
	end

	---@type boolean
	local sbuf_ok = pcall(function()
		return vim.api.nvim_set_current_buf(c_bufnr)
	end)
	if not sbuf_ok then
		---@type string
		local err = "ninjection.child:init_buf() error: Failed to set child bufnr."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	---@type string[]
	local text_lines = vim.split(opts.text, "\n", { plain = true })
	---@type boolean
	local sline_ok = pcall(vim.api.nvim_buf_set_lines, c_bufnr, 0, -1, false, text_lines)
	if not sline_ok then
		---@type string
		local err = "ninjection.child:init_buf() error: Failed to set buffer lines."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	---@type boolean
	local sname_ok = pcall(vim.api.nvim_buf_set_name, c_bufnr, self.p_name .. ":" .. c_bufnr .. ":" .. self.c_ft)
	if not sname_ok then
		---@type string
		local err = "ninjection.child:init_buf() error: Failed to set buffer name."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	---@type boolean
	local sft_ok = pcall(function()
		return vim.api.nvim_set_option_value("filetype", self.c_ft, { buf = c_bufnr })
	end)
	if not sft_ok then
		---@type string
		local err = "ninjection.child:init_buf() error: Failed to set filetype."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	---@type boolean
	local autocmd_ok = pcall(function()
		return vim.cmd("doautocmd FileType " .. self.c_ft)
	end)
	if not autocmd_ok then
		---@type string
		local err = "ninjection.child:init_buf() error: Failed to set run FileType autocmd."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	-- Preserve indentation after creating and pasting buffer contents, before
	-- autoformatting, or they will be lost.
	if cfg.preserve_indents then
		---@type NJIndents?, string?
		local p_indents, ind_err = require("ninjection.buffer").get_indents(0)
		if not p_indents then
			-- Initialized to 0 if unset
			p_indents = { t_indent = 0, b_indent = 0, l_indent = 0, tab_indent = 0 }

			if cfg.debug then
				vim.notify(
					"ninjection.child:init_buf() warning: Unable to preserve indentation "
						.. "with get_indents(): "
						.. tostring(ind_err),
					vim.log.levels.WARN
				)
			end
			-- Don't return early on indentation errors
		end
		---@cast p_indents NJIndents
		self.p_indents = p_indents
	end

	---@type boolean, string?
	local set_ok, set_nj_err = self:update_buf()
	if not set_ok then
		return false, tostring(set_nj_err)
	end

	return true, nil
end

---@nodoc
-- Update the ninjection state table for the child buffer.
-- This overwrites the ninjection table for the buffer if it exists.
-- Ninjection does not support nested parent -> child -> parent buffer relationships,
-- So this shouldn't be an issue. A parent should never become a child and vice-versa.
---@return boolean success, string? err
function NJChild:update_buf()
	-- Save the child information to the buffer's ninjection table
	if not vim.api.nvim_buf_is_valid(self.c_bufnr) then
		local err = "ninjection.child:update() error: Child buffer, " .. self.c_bufnr .. " is invalid."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	local set_nj_ok = pcall(function()
		return vim.api.nvim_buf_set_var(self.c_bufnr, "ninjection", self)
	end)
	if not set_nj_ok then
		---@type string
		local err = "ninjection.child:set_nj_table() error: Failed to update ninjection table with child object."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	return true, nil
end

-- Cross check the p_bufnr to ensure that the c_bufnr is registered as a child.
---@return NJParent? nj_parent, string? err
function NJChild:get_parent()
	if not vim.api.nvim_buf_is_valid(self.c_bufnr) then
		---@type string
		local err = "ninjection.child.NJChild:get_parent() error: The buffer " .. self.c_bufnr .. " is invalid."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end

	---@type boolean, NJParent?
	local get_njp_ok, get_njp_return = pcall(function()
		return vim.api.nvim_buf_get_var(self.p_bufnr, "ninjection")
	end)

	if not get_njp_ok then
		---@type string
		local err = "ninjection.child.NJChild:get_parent() error: The buffer "
			.. self.p_bufnr
			.. " did not return a ninjection table."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	elseif not get_njp_return or not require("ninjection.parent").is_parent(get_njp_return) then
		local err = "ninjection.child.NJChild:get_parent() error: This buffer appears to be an orphan: The child buffer "
			.. self.c_bufnr
			.. " has the parent buffer "
			.. self.p_bufnr
			.. " But that buffer has no ninjection table."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end
	---@cast get_njp_return NJParent

	---@type NJParent
	local nj_parent = get_njp_return
	if not vim.tbl_contains(nj_parent.children, self.c_bufnr) then
		---@type string
		local err = "ninjection.child.NJChild:get_parent() error: Ninjection table mismatch. Recorded parent buffer, "
			.. self.p_bufnr
			.. " does not have child buffer, "
			.. self.c_bufnr
			.. " indexed as a child in its ninjection table."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return nil, err
	end

	setmetatable(nj_parent, require("ninjection.parent"))
	return nj_parent, nil
end

---@return boolean success, string? err
function NJChild:format()
	local timeout = cfg.format_timeout or 500

	---@private
	---@param fmt_failed boolean
	---@param fmt_fn string?
	---@param fmt_err string?
	---@return boolean success, string? err
	local function fallback(fmt_failed, fmt_fn, fmt_err)
		if cfg.debug and fmt_failed then
			vim.notify(
				"ninjection.child:format(): warning format function call, "
					.. tostring(fmt_fn)
					.. " failed with error: "
					.. tostring(fmt_err)
					.. " ... Reverting to LSP formatting."
			)
		end
		if cfg.debug then
			vim.notify("ninjection.child:format() info: defaulting to LSP formatting", vim.log.levels.INFO)
		end
		local fmt_ok, err = pcall(vim.lsp.buf.format, {
			bufnr = self.c_bufnr,
			timeout_ms = timeout,
		})
		if not fmt_ok and cfg.debug then
			vim.notify("ninjection.child:format() fallback format error: " .. tostring(err), vim.log.levels.WARN)
		end
		return fmt_ok, err
	end

	---@type string?
	local cmd = cfg.format_cmd

	if cmd then
		---@type string[]
		local path = vim.split(cmd, ".", { plain = true })

		---@type unknown
		local fmt_fn = vim.tbl_get(_G, unpack(path))

		if type(fmt_fn) == "function" then
			---@type boolean, string?
			local fmt_ok, fmt_err = pcall(fmt_fn)
			if not fmt_ok then
				return fallback(true, fmt_fn, fmt_err)
			else
				return true, nil
			end
		else
			---@type boolean, string?
			local fmt_ok, fmt_err = pcall(function()
				vim.cmd(cmd)
			end)
			if not fmt_ok then
				return fallback(true, fmt_fn, fmt_err)
			else
				return true, nil
			end
		end
	end

	return fallback(false)
end

---@nodoc
--- Sets the child cursor to the same relative position as in the parent window.
--- @param opts NJChildCursor
--- @return boolean success, string? err
function NJChild:set_cursor(opts)
	if not self.c_win then
		---@type string
		local err = "ninjection.child:set_cursor() warning: Child bufnr " .. self.c_bufnr .. " has no window."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return false, nil
	end

	---@type integer[]
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

	---@type boolean, string?
	local set_cur_ok, set_cur_err = pcall(function()
		return vim.api.nvim_win_set_cursor(self.c_win, offset_cur)
	end)
	if not set_cur_ok then
		if cfg.debug then
			vim.notify(
				"ninjection.child:set_cursor() error: Setting cursor for window "
					.. self.c_win
					.. " ... "
					.. tostring(set_cur_err),
				vim.log.levels.ERROR
			)
		end
	end

	return true, nil
end

return NJChild
