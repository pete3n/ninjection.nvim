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

		require("conform").format({
			bufnr = buf,
			async = false,
			lsp_fallback = false,
		})

		local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		print("Formatted:", vim.inspect(out))
	end)
end)
