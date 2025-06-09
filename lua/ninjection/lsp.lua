---@module "ninjection.lsp"
---@brief
--- The buffer module contains helper functions utilized by the main ninjection
--- module for starting and managing LSP connections.
---
local M = {}
---@nodoc
---@type Ninjection.Config
local cfg = require("ninjection.config").values
local has_lspconfig, lspconfig = pcall(require, "lspconfig")
if not has_lspconfig then
	vim.notify("ninjection.nvim requires 'lspconfig' plugin for LSP features", vim.log.levels.ERROR)
	return
end

--- find a reference to: `vim.api.keyset.create_user_command.command_args`
---@tag lspconfig.Config
---@class lspconfig.Config : vim.lsp.ClientConfig
---@brief Annotation for lspconfig from `nvim-lspconfig/lua/lspconfig/configs.lua`

---@class LspDocumentConfig
---@field filetypes string[]
---@field cmd string[]

---@alias NJLspStatusMsg
---| "unmapped"
---| "unconfigured"
---| "unavailable"
---| "no-exec"
---| "unsupported"
---| "failed_start"
---| "started"

---@type NJLspStatusMsg
local LspStatusMsg = {
	UNMAPPED = "unmapped",
	UNCONFIGURED = "unconfigured",
	UNAVAILABLE = "unavailable",
	NO_EXEC = "no-exec",
	UNSUPPORTED = "unsupported",
	FAILED_START = "failed_start",
	STARTED = "started",
}
M.LspStatusMsg = LspStatusMsg

---@tag NJLspStatus
---@class NJLspStatus
---@brief Store LSP status and associated client ID.
---
---@field status NJLspStatusMsg - The LSP startup status.
---@field client_id integer? - The client ID of the started LSP, nil on failure
local NJLspStatus = {}
NJLspStatus.__index = NJLspStatus

--- Check if the client is attached to the given buffer and initialized
---@param bufnr integer
---@return boolean
function NJLspStatus:is_attached(bufnr)
	if self.status ~= LspStatusMsg.STARTED or not self.client_id then
		return false
	end

	local client = vim.lsp.get_client_by_id(self.client_id)
	if not client or not client.initialized then
		return false
	end

	return vim.lsp.buf_is_attached(bufnr, self.client_id)
end

---@param status NJLspStatusMsg
---@param client_id? integer
function NJLspStatus.new(status, client_id)
	return setmetatable({
		status = status,
		client_id = client_id,
	}, NJLspStatus)
end
M.NJLspStatus = NJLspStatus

-- Autocommands don't trigger properly when creating and arbitrarily assigning
-- filetypes to buffers, so we need a function to start the appropriate LSP.
---@tag ninjection.buffer.start_lsp()
---@brief
--- Starts an appropriate LSP for the provided language and attach it to bufnr.
---
--- Parameters ~
---@param lang string - The filetype of the injected language (e.g., "lua", "python").
---@param root_dir string - The root directory for the buffer.
---@param bufnr integer - The bufnr handle to attach the LSP to.
---
---@return NJLspStatus? result, string? err - The LSP status.
M.start_lsp = function(lang, root_dir, bufnr)
	-- The injected language must be mapped to an LSP
	---@type string?, string?
	local lang_lsp = cfg.lsp_map[lang]
	local err
	if not lang_lsp then
		err = "ninjection.buffer.start_lsp() warning: No LSP mapped to "
			.. "language: "
			.. lang
			.. " check your configuration."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return NJLspStatus.new(LspStatusMsg.UNMAPPED, nil), err
	end
	---@cast lang_lsp string

	-- The LSP must have an available configuration
	---@type boolean, lspconfig.Config?
	local ok, lsp_def = pcall(function()
		return lspconfig[lang_lsp] and lspconfig[lang_lsp].document_config
	end)
	if not ok or not lsp_def then
		err = "Ninjection.buffer.start_lsp() error: no LSP configuration for: " .. lang_lsp .. " " .. tostring(lsp_def)
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return NJLspStatus.new(LspStatusMsg.UNCONFIGURED, nil), err
	end
	---@cast lsp_def lspconfig.Config

	-- The LSP binary path must exist
	-- RPC function support is not implemented
	---@type string[]|fun(dispatchers: vim.lsp.rpc.Dispatchers): vim.lsp.rpc.PublicClient?
	local lsp_cmd = lsp_def.cmd
	if not lsp_cmd or #lsp_cmd == 0 then
		err = "ninjection.buffer.start_lsp() warning: Command to execute "
			.. lang_lsp
			.. " does not exist. Ensure it is installed and configured."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return NJLspStatus.new(LspStatusMsg.UNAVAILABLE, nil), err
	end
	---@cast lsp_cmd string[]

	-- The LSP binary path must be executable
	-- The command must be the first element
	---@type unknown?
	local is_executable
	ok, is_executable = pcall(function()
		return vim.fn.executable(lsp_cmd[1])
	end)
	if not ok or is_executable ~= 1 then
		err = "ninjection.buffer.start_lsp() warning: The LSP command: "
			.. lsp_cmd[1]
			.. " is not executable. "
			.. tostring(is_executable)
		vim.notify(err, vim.log.levels.WARN)
		return NJLspStatus.new(LspStatusMsg.NO_EXEC, nil), err
	end
	---@cast is_executable integer

	-- The LSP must support our injected language
	if not vim.tbl_contains(lsp_def.filetypes, lang) then
		err = "ninjection.buffer.start_lsp() warning: The configured LSP: "
			.. lang_lsp
			.. " does not support "
			.. lang
			.. " modify your configuration "
			.. " to use an appropriate LSP."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return NJLspStatus.new(LspStatusMsg.UNSUPPORTED, nil), err
	end

	---@type integer?
	local client_id = vim.lsp.start({
		name = lang_lsp,
		cmd = lsp_cmd,
		root_dir = root_dir,
		bufnr = bufnr,
	})
	if client_id then
		vim.lsp.buf_attach_client(bufnr, client_id)
	else
		err = "ninjection.buffer.start_lsp() warning: The LSP: "
			.. lang_lsp
			.. " did not return a client_id, check your language client logs "
			.. "(default ~/.local/state/nvim/lsp.log) for more information."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return NJLspStatus.new(LspStatusMsg.FAILED_START, nil), err
	end
	---@cast client_id integer

	return NJLspStatus.new(LspStatusMsg.STARTED, client_id), nil
end

return M
