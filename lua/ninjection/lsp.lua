---@module "ninjection.lsp"
---@brief
--- The buffer module contains helper functions utilized by the main ninjection
--- module for starting and managing LSP connections.
---

---@type NinjectionConfig
local cfg = setmetatable({}, {
	__index = function(_, key)
		return require("ninjection.config").values[key]
	end,
})

---@alias NJLspStatusResponseType
---| "unmapped"
---| "unconfigured"
---| "no-exec"
---| "no-rpc"
---| "failed_start"
---| "started"

---@class NJLspStatusMsg
---@field UNMAPPED "unmapped"
---@field UNCONFIGURED "unconfigured"
---@field NO_EXEC "no-exec"
---@field NO_RPC "no-rpc"
---@field FAILED_START "failed_start"
---@field STARTED "started"

---@type NJLspStatusMsg
local LspStatusMsg = {
	UNMAPPED = "unmapped",
	UNCONFIGURED = "unconfigured",
	NO_EXEC = "no-exec",
	NO_RPC = "no-rpc",
	FAILED_START = "failed_start",
	STARTED = "started",
}
M.LspStatusMsg = LspStatusMsg

---@tag NJLspStatus
---@class NJLspStatus
---@brief Store LSP status and associated client ID.
---
---@field status NJLspStatusResponseType - The LSP startup status.
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

---@param status NJLspStatusResponseType
---@param client_id? integer
function NJLspStatus.new(status, client_id)
	assert(
		LspStatusMsg[status:upper()],
		"ninjection.buffer.NJLspStatus.new() error: Invalid LSP status: " .. tostring(status)
	)
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
---@param bufnr integer - The bufnr handle to attach the LSP to.
---
---@return NJLspStatus? result, string? err - The LSP status.
function M.start_lsp(lang, bufnr)
	-- The injected language must be mapped to an LSP
	---@type string?
	local lang_lsp = cfg.lsp_map[lang]
	if not lang_lsp then
		---@type string
		local err = "ninjection.lsp.start_lsp() warning: No LSP mapped to "
			.. "language: "
			.. lang
			.. " check your configuration."
		if cfg.debug then
			vim.notify(err, vim.log.levels.WARN)
		end
		return NJLspStatus.new(LspStatusMsg.UNMAPPED, nil), err
	end
	---@cast lang_lsp string

	---@type vim.lsp.ClientConfig
	local lsp_cfg = vim.lsp.config[lang_lsp]

	if not lsp_cfg then
		---@type string
		local err = "ninjection.lsp.start_lsp() error: LSP, " .. lang_lsp .. " is not configured."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return NJLspStatus.new(LspStatusMsg.UNCONFIGURED, nil), err
	end

	if type(lsp_cfg.cmd) == "function" then
		-- Advanced users may be using a dynamic client
		local err = "ninjection.lsp.start_lsp() error: dynamic RPC clients are not supported."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return NJLspStatus.new(LspStatusMsg.NO_RPC, nil), err
	elseif type(lsp_cfg.cmd) == "table" and not vim.fn.executable(lsp_cfg.cmd[1]) then
		local err = "ninjection.lsp.start_lsp() error: LSP executable, "
			.. tostring(lsp_cfg.cmd[1])
			.. " not found in $PATH."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return NJLspStatus.new(LspStatusMsg.NO_EXEC, nil), err
	end

	---@type integer?
	local client_id = vim.lsp.start(lsp_cfg, { bufnr = bufnr })
	if not client_id then
		---@type string
		local err = "ninjection.lsp.start_lsp() warning: The LSP, "
			.. lang_lsp
			.. " with the configuration: "
			.. vim.inspect(lsp_cfg)
			.. " lsp.start() did not return a client_id, check your LSP logs "
			.. "(default ~/.local/state/nvim/lsp.log) for more information."
		if cfg.debug then
			vim.notify(err, vim.log.levels.ERROR)
		end
		return NJLspStatus.new(LspStatusMsg.FAILED_START, nil), err
	end
	---@cast client_id integer

	return NJLspStatus.new(LspStatusMsg.STARTED, client_id), nil
end

return M
