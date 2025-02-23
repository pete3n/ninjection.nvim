---@class NinjectionSubcommand
---@field impl fun(args?: string[], opts?: table)
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
end

vim.api.nvim_create_user_command("Ninjection", ninjection_cmd, {
  nargs = "+",
  desc = "Ninjection plugin command with subcommand support",
  bang = false,
  complete = function(arg_lead, cmdline, _)
    -- Try to match the subcommand and its argument lead using a pattern
    local subcmd_key, subcmd_arg_lead = cmdline:match("^['<,'>]*Ninjection[!]*%s+(%S+)%s*(.*)$")
    if subcmd_key and subcmd_arg_lead and subcommand_tbl[subcmd_key] and subcommand_tbl[subcmd_key].complete then
      -- Provide completions for the subcommand's arguments
      return subcommand_tbl[subcmd_key].complete(subcmd_arg_lead)
    end

    -- If no subcommand (or no argument provided yet), suggest subcommand names
    local keys = vim.tbl_keys(subcommand_tbl)
    return vim.tbl_filter(function(key)
      return key:find(arg_lead)
    end, keys)
  end,
})
