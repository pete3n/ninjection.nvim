package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path
require("helpers.init")

local eq = assert.are.same
local njhealth = require("ninjection.health")

print(vim.inspect(vim.opt.rtp:get()))

describe("ninjection.checkhealth integration test #e2e #edit", function()
	it("validates checkhealth requirements", function()
		njhealth.check()
		local buf_content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local expected = {
			"==============================================================================",
			"ninjection:                                                                 ✅",
			"",
			"Checking Neovim version >= 0.11.0 ~",
			"- ✅ OK Neovim >= 0.11.0 detected",
			"",
			"Checking for required plugins ~",
			"- ✅ OK lspconfig installed.",
			"- ✅ OK nvim-treesitter installed.",
			"- ✅ OK conform installed.",
			"",
			"Checking configuration ~",
			"- ✅ OK valid config.",
			"",
		}
		print("Buffer content: " .. vim.inspect(buf_content))

		eq(expected, buf_content)
	end)
end)
