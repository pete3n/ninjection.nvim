---@module "ninjection.child"
---@brief
--- The buffer module contains the ninjection child object class.
---

---@nodoc
---@type Ninjection.Config
local cfg = require("ninjection.config").values

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

	--TODO: Replace with format function with Conform/LSP support
	-- Detect Conform and gracefully fallback to LSP if not present, with warning
	if cfg.auto_format then
		---@type boolean
		local fmt_ok = pcall(function()
			return vim.cmd("lua " .. cfg.format_cmd)
		end)
		if not fmt_ok then
			if cfg.debug then
				vim.notify(
					'ninjection.child:init_buf() warning: Calling vim.cmd("lua "'
						.. tostring(cfg.format_cmd)
						.. ")\n",
					vim.log.levels.WARN
				)
				-- Don't return early on auto-format error
			end
		end
	end

	---@type boolean, string?
	local set_ok, set_nj_err = self:set_nj_table()
	if not set_ok then
		return false, tostring(set_nj_err)
	end

	return true, nil
end


-- This overwrites the ninjection table for the buffer if it exists.
-- Ninjection does not support nested parent -> child -> parent buffer relationships,
-- So this shouldn't be an issue. A parent should never become a child and vice-versa.
---@return boolean success, string? err
function NJChild:set_nj_table()
	-- Save the child information to the buffer's ninjection table
	if not vim.api.nvim_buf_is_valid(self.c_bufnr) then
		local err = "ninjection.child:set_nj_table() error: Child buffer is invalid."
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

	return nj_parent, nil
end

return NJChild
