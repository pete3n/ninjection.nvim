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

local ts = require("vim.treesitter")
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
	---@type boolean, unknown, string?, integer?, string?, string?
	local ok, raw_output, err, p_bufnr, inj_node_text, inj_node_lang

	ok, raw_output = pcall(function()
		return vim.api.nvim_get_current_buf()
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	if type(raw_output) ~= "number" then
		error("ninjection.edit() error: Could not retrieve current buffer handle.", 2)
	end
	p_bufnr = raw_output
	---@cast p_bufnr integer

	---@type NJNodeTable?
	local inj_node_info
	inj_node_info, err = parse.get_node_table(p_bufnr)
	if not inj_node_info then
		if cfg.debug then
			vim.notify(
				"ninjection.edit() waring: Failed to get injected node " .. "information: " .. tostring(err),
				vim.log.levels.WARN
			)
		end
		return nil
	end
	---@cast inj_node_info NJNodeTable

	if inj_node_info.node then
		ok, raw_output = pcall(function()
			return ts.get_node_text(inj_node_info.node, p_bufnr)
		end)
		if not ok then
			error(tostring(raw_output), 2)
		end
		inj_node_text = raw_output
		if not inj_node_text or inj_node_text == "" then
			vim.notify(
				"ninjection.edit() warning: Failed to get injected node text "
					.. "calling vim.treesitter.get_node_text()",
				vim.log.levels.WARN
			)
			return nil
		end
	end
	---@cast inj_node_text string

	if not inj_node_info.range then
		vim.notify(
			"ninjection.edit() warning: Failed to retrieve valid range "
				.. "for injected content calling get_node_table().",
			vim.log.levels.WARN
		)
		return nil
	end

	inj_node_lang, err = parse.get_inj_lang(p_bufnr)
	if not inj_node_lang or inj_node_lang == "" then
		error(
			"ninjection.edit() error: Failed to get injected node language "
				.. "calling get_inj_lang(): "
				.. tostring(err),
			2
		)
	end
	---@cast inj_node_lang string

	ok, raw_output = pcall(function()
		return vim.api.nvim_win_get_cursor(0)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end

	---@type integer[]?
	local p_cursor
	if type(raw_output) == "table" then
		p_cursor = raw_output
		---@cast p_cursor integer[]
	elseif cfg.debug then
		vim.notify(
			"ninjection.edit() warning: No cursor position returned from " .. "vim.api.nvim_win_get_cursor(0)",
			vim.log.levels.WARN
		)
		p_cursor = {}
		-- Don't return on failed cursor
	end
	---@cast p_cursor integer[]

	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_name(0)
	end)
	if not ok then
		error(tostring(raw_output), 2)
	end
	if type(raw_output) ~= "string" then
		if cfg.debug then
			vim.notify(
				"ninjection.edit() warning: No name returned from " .. "vim.api.nvim_buf_get_name(0)",
				vim.log.levels.WARN
			)
		end
		return nil
	end
	---@type string
	local p_name = raw_output

	---@type string
	local root_dir
	-- Try getting the first workspace folder.
	ok, raw_output = pcall(function()
		return vim.lsp.buf.list_workspace_folders()[1]
	end)
	if ok and type(raw_output) == "string" and raw_output ~= "" then
		root_dir = raw_output
	else
		-- Fall back to the current working directory.
		local nested_ok, nested_raw_output = pcall(function()
			return vim.fn.getcwd()
		end)
		if nested_ok and type(nested_raw_output) == "string" and nested_raw_output ~= "" then
			root_dir = nested_raw_output
		else
			error(
				"ninjection.edit() error: Could not retrieve workspace directory "
					.. "or current directory.\nvim.lsp.buf.list_workspace_folders()[1] error: "
					.. tostring(raw_output)
					.. "\nvim.fn.getcwd() error: "
					.. tostring(nested_raw_output),
				2
			)
		end
	end
	if not root_dir or root_dir == "" then
		error("ninjection.edit() error: Unknown error setting root_dir", 2)
	end

	--TODO: Conditional text transform based on languages
	---@type string[]
	local lines = vim.split(inj_node_text, "\n")
	if lines[1]:match("^%s*''%s*$") then
		table.remove(lines, 1)
	end
	if lines[#lines]:match("^%s*''%s*$") then
		table.remove(lines, #lines)
	end
	---@type string
	local trimmed_text = table.concat(lines, "\n")

	---@type {bufnr: integer?, win: integer?, indents: NJIndents}
	local c_table
	c_table, err = buffer.create_child(p_bufnr, p_name, inj_node_info.range, root_dir, trimmed_text, inj_node_lang)
	if not c_table.bufnr or not c_table.win then
		error("ninjection.edit() error: Could not create child buffer and window: " .. tostring(err), 2)
	end

	if cfg.preserve_indents then
		buffer.set_child_cur(c_table.win, p_cursor, inj_node_info.range.s_row, c_table.indents)
	else
		buffer.set_child_cur(c_table.win, p_cursor, inj_node_info.range.s_row)
	end

	---@type NJLspStatus?
	local lsp_status
	lsp_status, err = buffer.start_lsp(inj_node_lang, root_dir)
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
	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_get_var(p_bufnr, "ninjection")
	end)
	if ok and type(raw_output) == "table" then
		p_ninjection = raw_output
	else
		err = tostring(raw_output)
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
	ok, raw_output = pcall(function()
		return vim.api.nvim_buf_set_var(p_bufnr, "ninjection", p_ninjection)
	end)
	if not ok then
		error(tostring(raw_output), 2)
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
