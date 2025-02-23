---@class NinjectionSubcommand
---@field impl fun()
---@field complete? fun(arg_lead: string): string[]

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

local function ninjection_cmd(opts)
	local fargs = opts.fargs
	local subcommand_key = fargs[1]

	if not subcommand_key or not subcommand_tbl[subcommand_key] then
		vim.notify("Ninjection: Unknown subcommand: " .. tostring(subcommand_key), vim.log.levels.ERROR)
		return
	end

	-- Directly execute the subcommand's implementation
	subcommand_tbl[subcommand_key].impl()
end

vim.api.nvim_create_user_command("Ninjection", ninjection_cmd, {
	nargs = 1, -- exactly one argument: the subcommand
	desc = "Ninjection plugin command with subcommand support",
	bang = false,
	complete = function(arg_lead)
		local keys = vim.tbl_keys(subcommand_tbl)
		return vim.tbl_filter(function(key)
			return key:find(arg_lead)
		end, keys)
	end,
})
