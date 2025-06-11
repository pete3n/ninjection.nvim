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

		require("conform").setup({
			formatters_by_ft = {
				lua = { "stylua" },
			},
			formatters = {
				stylua = {
					command = "echo",
					args = { "STYLUA CALLED" },
					stdin = true,
				},
			},
		})

		local f = io.open("/debug/debug_log.txt", "a")
		f:write("stylua path: ", vim.fn.exepath("stylua"), "\n")
		f:write("stylua version: ", vim.fn.system("stylua --version"), "\n")
		f:close()

		require("conform").format({
			bufnr = buf,
			async = false,
			lsp_fallback = false,
		})

		local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		vim.notify("Formatted: " .. vim.inspect(out))
	end)
end)
