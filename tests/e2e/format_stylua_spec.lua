package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path
require("helpers.init")

describe("stylua manual format test #e2e #stylua", function()
	it("formats Lua with stylua", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
			"local lua_content",
			"  local more_lua_content",
		})
		vim.bo[buf].filetype = "lua"

		local conform = require("conform")

		-- SETUP MUST BE CALLED FIRST
		conform.setup({
			formatters_by_ft = {
				lua = { "stylua" },
			},
			formatters = {
				stylua = {
					prepend_args = { "--indent-width", "2" },
				},
			},
		})

		-- Confirm stylua is found
		vim.notify("stylua path: " .. vim.fn.exepath("stylua"))
		vim.notify("stylua version: " .. vim.fn.system("stylua --version"))
		vim.notify("Detected formatters: " .. vim.inspect(conform.list_formatters_for_buffer(buf)))

		conform.format({
			bufnr = buf,
			async = false,
			lsp_fallback = false,
		})

		local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		vim.notify("Formatted: " .. vim.inspect(out))
	end)
end)
