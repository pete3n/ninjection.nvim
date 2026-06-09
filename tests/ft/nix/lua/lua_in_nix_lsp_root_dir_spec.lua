package.path = vim.fn.getcwd() .. "/tests/e2e/?.lua;" .. package.path

local lsp = require("ninjection.lsp")

-- Regression for the function-form `root_dir` crash.
--
-- nvim-lspconfig / nixvim configure `vim.lsp.config.lua_ls.root_dir` as a
-- *function* (the `fun(bufnr, on_dir)` form). `vim.lsp.start()` does not resolve
-- that form (only the `vim.lsp.enable` autostart path does), so handing the
-- config through verbatim left `client.root_dir` a function. That hung the
-- synchronous start and crashed downstream plugins that call
-- `vim.fs.normalize(client.root_dir)` -- e.g. lazydev:
--   "vim/fs.lua: path: expected string, got function".
-- start_lsp() must pin a concrete string root before starting the client.
describe("ninjection.lsp.start_lsp dynamic root_dir #e2e #lua-nix #lsp", function()
	local saved_lua_ls
	local started_client_id

	before_each(function()
		saved_lua_ls = vim.lsp.config["lua_ls"]
	end)

	after_each(function()
		if started_client_id then
			local client = vim.lsp.get_client_by_id(started_client_id)
			if client then
				pcall(function()
					client:stop(true)
				end)
			end
			started_client_id = nil
		end
		vim.lsp.config["lua_ls"] = saved_lua_ls
	end)

	it("pins a string root_dir when the config provides a function", function()
		local dynamic_cfg = vim.deepcopy(vim.lsp.config["lua_ls"] or {})
		dynamic_cfg.root_dir = function(_, on_dir)
			on_dir(vim.fn.getcwd())
		end
		vim.lsp.config["lua_ls"] = dynamic_cfg

		local child_bufnr = vim.api.nvim_create_buf(true, true)
		vim.api.nvim_buf_set_lines(child_bufnr, 0, -1, false, { "local x = 1" })
		vim.api.nvim_set_option_value("filetype", "lua", { buf = child_bufnr })

		local status, err = lsp.start_lsp("lua", child_bufnr, vim.fn.getcwd())

		-- Skip gracefully when the language server binary is unavailable.
		if status and status.status == lsp.LspStatusMsg.NO_EXEC then
			print("[INFO] lua-language-server not on PATH; skipping root_dir assertion")
			return
		end

		assert.are.equal(lsp.LspStatusMsg.STARTED, status and status.status, tostring(err))
		assert.is_truthy(status.client_id)
		started_client_id = status.client_id

		local client = vim.lsp.get_client_by_id(status.client_id)
		assert.is_truthy(client)
		-- The crash precondition: client.root_dir must be a usable string.
		assert.are.equal("string", type(client.root_dir))
		local normalize_ok = pcall(vim.fs.normalize, client.root_dir)
		assert.is_true(normalize_ok, "vim.fs.normalize must accept client.root_dir")

		-- The shared global config must not have been mutated by start_lsp.
		assert.are.equal("function", type(vim.lsp.config["lua_ls"].root_dir))
	end)
end)
