local health = require("vim.health")

local M = {}

function M.check()
	health.start("ninjection.nvim Health Check")

  -- Check for the Treesitter dependency (nvim-treesitter)
  local ok, _ = pcall(require, "nvim-treesitter")
  if ok then
    health.ok("nvim-treesitter is installed.")
  else
    health.error("nvim-treesitter is not installed. Please install it.")
	end
end

return M
