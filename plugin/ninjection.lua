---@type table<string, Ninjection.Subcommand>
local subcommand_tbl = {
	edit = {
		impl = function()
			require("ninjection").edit()
		end,
	},
	replace = {
		impl = function()
			require("ninjection").replace()
		end,
	},
	select = {
		impl = function()
			require("ninjection").select()
		end,
	},
}

---@param opts Ninjection.CmdOpts
---@return nil
local function ninjection_cmd(opts)
	---@type string[]
	local fargs = opts.fargs
	---@type string
	local subcommand_key = fargs[1]

	if not subcommand_key or not subcommand_tbl[subcommand_key] then
		---@type string
		local available = table.concat(vim.tbl_keys(subcommand_tbl), ", ")
		vim.notify(
			"Ninjection: Unknown subcommand: " .. tostring(subcommand_key) .. ". Available subcommands: " .. available,
			vim.log.levels.ERROR
		)
		return
	end

	subcommand_tbl[subcommand_key].impl()
end

vim.api.nvim_create_user_command("Ninjection", ninjection_cmd, {
	nargs = 1, -- exactly one argument: the subcommand
	desc = "Ninjection plugin command with subcommand support",
	bang = false,
	---@param arg_lead string
	---@return string[]
	complete = function(arg_lead)
		local keys = vim.tbl_keys(subcommand_tbl)
		return vim.tbl_filter(function(key)
			return key:find(arg_lead)
		end, keys)
	end,
})

vim.keymap.set("n", "<Plug>(NinjectionEdit)", function()
	require("ninjection").edit()
end, { noremap = true, silent = true })
vim.keymap.set("n", "<Plug>(NinjectionReplace)", function()
	require("ninjection").replace()
end, { noremap = true, silent = true })
vim.keymap.set("n", "<Plug>(NinjectionSelect)", function()
	require("ninjection").select()
end, { noremap = true, silent = true })
