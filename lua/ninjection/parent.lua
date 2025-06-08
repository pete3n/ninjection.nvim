---@module "ninjection.parent"
---@brief
--- The buffer module contains the ninjection parent object class.
---

---@nodoc
---@type Ninjection.Config
local cfg = require("ninjection.config").values

---@tag NJParent
---@brief Stores associated child bufnrs.
---
---@class NJParent
---@field type "NJParent"
---@field children integer[]
local NJParent = {}
NJParent.__index = NJParent


-- Make 'type' field immutable
function NJParent.__newindex(t, k, v)
  if k == "type" then
    error("Cannot modify field 'type' of NJChild")
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
---  children?: integer[] }
---
---@return NJParent
function NJParent.new(opts)
	local self = setmetatable({
		children = opts.children,
	}, NJParent)

	return self
end

-- This overwrites the ninjection table for the buffer if it exists.
-- Ninjection does not support nested parent -> child -> parent buffer relationships,
-- So this shouldn't be an issue. A parent should never become a child and vice-versa.
---@param p_bufnr integer
---@return boolean success, string? err
function NJParent:set_nj_table(p_bufnr)
	-- Save the child information to the buffer's ninjection table
	if not vim.api.nvim_buf_is_valid(p_bufnr) then
		local err = "ninjection.buffer.init_child() error: Child buffer is invalid."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	local set_nj_ok = pcall(function()
		return vim.api.nvim_buf_set_var(p_bufnr, "ninjection", self)
	end)
	if not set_nj_ok then
		---@type string
		local err = "ninjection.buffer.init_child() error: Failed to update ninjection table with child object."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return false, err
	end

	return true, nil
end

---@param c_bufnr integer
---@return boolean success, string? err
function NJParent:del_child(c_bufnr)
	---@type integer, integer
	for i, bufnr in ipairs(self.children) do
		if bufnr == c_bufnr then
			table.remove(self.children, i)
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

return NJParent
