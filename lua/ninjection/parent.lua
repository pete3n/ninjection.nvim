---@module "ninjection.parent"
---@brief
--- The buffer module contains the ninjection parent object class.
---

---@nodoc
---@type Ninjection.Config
local cfg = require("ninjection.config").values

---@tag NJParent
---@brief Stores parent buffer information and associated child bufnrs.
---
---@class NJParent
---@field type "NJParent"
---@field p_bufnr integer Parent buffer number
---@field p_ft string Parent buffer filetype
---@field p_name string Parent buffer name
---@field children? integer[] Child bufnrs associated with this parent
local NJParent = {}
NJParent.__index = NJParent

-- Make 'type' field immutable
function NJParent.__newindex(t, k, v)
	if k == "type" then
		error("Cannot modify field 'type' of NJParent")
	else
		rawset(t, k, v)
	end
end

---@param obj any
---@return boolean
function NJParent.is_parent(obj)
	return type(obj) == "table" and obj.type and obj.type == "NJParent"
end

---@param opts {
---  p_bufnr: integer,
---  p_ft: string,
---  p_name: string,
---  children?: integer[] }
---
---@return NJParent
function NJParent.new(opts)
	local self = setmetatable({
		p_bufnr = opts.p_bufnr,
		p_ft = opts.p_ft,
		p_name = opts.p_name,
		children = opts.children,
	}, NJParent)
	-- Bypass __newindex to set immutable type
	rawset(self, "type", "NJParent")

	-- Sync new parent object with ninjection state table
	self:update_buf()
	return self
end

---@nodoc
-- Update the ninjection state table in the parent buffer.
-- This overwrites the ninjection table for the buffer if it exists.
-- Ninjection does not support nested parent -> child -> parent buffer relationships.
-- A parent should never become a child and vice-versa.
---@return boolean success, string? err
function NJParent:update_buf()
	if not vim.api.nvim_buf_is_valid(self.p_bufnr) then
		local err = "ninjection.parent:update() error: Bufnr, " .. self.p_bufnr .. " is invalid."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	local set_nj_ok = pcall(function()
		return vim.api.nvim_buf_set_var(self.p_bufnr, "ninjection", self)
	end)
	if not set_nj_ok then
		---@type string
		local err = "ninjection.parent:update() error: Failed to update parent ninjection table."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	return true, nil
end

---@nodoc
--- Associate a child bufnr with the parent bufnr
---@param c_bufnr integer
---@return boolean success, string? err
function NJParent:add_child(c_bufnr)
	if not vim.api.nvim_buf_is_valid(self.p_bufnr) then
		---@type string
		local err = "ninjection.parent:add_child() error: The parent buffer, " .. self.p_bufnr .. " is invalid."
		if cfg.debug then
			vim.notify(err, vim.log.level.ERROR)
		end
		return false, err
	end

	if not vim.api.nvim_buf_is_valid(c_bufnr) then
		---@type string
		local err = "ninjection.parent:add_child() error: The child buffer, " .. c_bufnr .. " is invalid."
		if cfg.debug then
			vim.notify(err, vim.log.level.ERROR)
		end
		return false, err
	end

	-- A parent buffer should be initialized with a ninjection table when created,
	-- So if it can't be retrieved then we are in a bad state.
	---@type boolean, NJParent?
	local get_nj_ok, nj_parent = pcall(vim.api.nvim_buf_get_var, self.p_bufnr, "ninjection")
	if not get_nj_ok or not NJParent.is_parent(nj_parent) then
		---@type string
		local err = "ninjection.parent.add_child() error: Parent bufnr "
			.. self.p_bufnr
			.. " does not have a valid parent ninjection table."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end
	---@cast nj_parent NJParent

	-- Ensure children table exists in the case of a new parent
	self.children = self.children or {}

	-- Avoid duplicate child entries
	if not vim.tbl_contains(self.children, c_bufnr) then
		table.insert(self.children, c_bufnr)
	end

	self:update_buf() -- Sync with the parent buffer's ninjection state table

	return true, nil
end

---@nodoc
--- Delete a child buffer, remove it from the parent, and update the parent table.
---@param c_bufnr integer
---@return boolean success, string? err
function NJParent:del_child(c_bufnr)
	---@type integer, integer
	for i, bufnr in ipairs(self.children) do
		if bufnr == c_bufnr then
			local clients = vim.lsp.get_clients({ bufnr = c_bufnr })
			for _, client in ipairs(clients) do
				pcall(vim.lsp.buf_detach_client, c_bufnr, client.id)
			end
			if vim.api.nvim_buf_is_valid(c_bufnr) then
				vim.api.nvim_buf_delete(c_bufnr, { force = true })
			end
			table.remove(self.children, i)
			self:update_buf()
			return true, nil
		end
	end

	---@type string
	local err = "ninjection.parent:del_child(): bufnr " .. c_bufnr .. " not found in parent."
	if cfg.debug then
		vim.notify(err, vim.error.levels.ERROR)
	end

	return false, err
end

---@nodoc
--- Replace lines in a given range with replacement text.
---@param rep_lines string[]
---@param range NJRange
---@return boolean success, string? err
function NJParent:replace_range(rep_lines, range)
	---@type { open: string, close: string }?
	local delimiters = cfg.format_delimiters[self.p_ft]
	if not delimiters or type(delimiters) ~= "table" then
		---@type string
		local err = "ninjection.parent:replace_range() error: No injected code comment delimiters defined "
			.. "for the language"
			.. self.p_ft
			.. " please check your format_delimiters configuration table."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	if not rep_lines or vim.tbl_isempty(rep_lines) then
		---@type string
		local err = "ninjection.parent:replace_range() error: No replacement lines found."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return false, err
	end

	---@type string
	local parent_line = vim.api.nvim_buf_get_lines(self.p_bufnr, range.s_row - 1, range.s_row, false)[1] or ""
	---@type string
	local parent_indent = parent_line:match("^(%s*)") or ""
	---@type string
	local delimiter_indent = parent_indent .. string.rep(" ", cfg.format_indent)
	---@type string
	local child_indent = delimiter_indent .. string.rep(" ", cfg.format_indent)

	---@type string[]
	local delimited_lines = {}
	table.insert(delimited_lines, delimiter_indent .. delimiters.open)
	for _, line in ipairs(rep_lines) do
		table.insert(delimited_lines, child_indent .. line)
	end
	table.insert(delimited_lines, delimiter_indent .. delimiters.close)

	---@type boolean, string?
	local set_lines_ok, set_lines_err =
		pcall(vim.api.nvim_buf_set_lines, self.p_bufnr, range.s_row, range.e_row + 1, false, delimited_lines)
	if not set_lines_ok then
		---@type string
		local err = "ninjection.parent:replace_range(): Error setting lines in parent bufnr, "
			.. self.p_bufnr
			.. " for range, "
			.. range.s_row
			.. " to "
			.. range.e_row
			.. " ... "
			.. set_lines_err
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	return true, nil
end

return NJParent
