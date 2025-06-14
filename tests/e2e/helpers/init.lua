local packpath = vim.env.NVIM_PACKPATH
local rtp = vim.env.NVIM_RTP
local vimruntime = vim.env.VIMRUNTIME

local lspconfig_ok, lspconfig = pcall(require, "lspconfig")
local servers = {}

if lspconfig_ok then
	for name, config in pairs(lspconfig) do
		if type(config) == "table" and config.cmd then
			table.insert(servers, {
				name = name,
				cmd = config.cmd,
			})
		end
	end
end

--local f = io.open("/debug/debug_log.txt", "a")
--if f then
--  f:write("This ran!\n")
--  f:close()
--end

local f = io.open("/debug/debug_log.txt", "a")

if f then
  f:write("[DEBUG INIT] Checking lua_ls config...\n")

  if lspconfig and lspconfig.lua_ls then
    f:write("lua_ls config exists!\n")
    f:write("lua_ls.cmd = " .. vim.inspect(lspconfig.lua_ls.cmd) .. "\n")

    local handle = io.popen("which lua-language-server 2>/dev/null")
    local path = handle and handle:read("*a") or "not found"
    if handle then handle:close() end

    f:write("which lua-language-server: " .. path .. "\n")
  else
    f:write("lua_ls is NOT defined in lspconfig.\n")
  end

  f:close()
end

if rtp and rtp ~= "" then
	vim.opt.rtp = { rtp }
	print("Runtime path set to:", vim.inspect(vim.opt.rtp:get()))
end

if vimruntime and vimruntime ~= "" then
	package.path = vimruntime .. "/lua/?.lua;" .. vimruntime .. "/lua/?/init.lua;" .. package.path
	print("Updated package.path with VIMRUNTIME:", package.path)
end

local project_root = vim.fn.getcwd()
-- Prepend the plugin's lua directory to package.path so that require("ninjection") finds lua/ninjection/init.lua
package.path = project_root .. "/lua/?.lua;" .. project_root .. "/lua/?/init.lua;" .. package.path

print("Updated package.path:", package.path)

if packpath and packpath ~= "" then
	vim.opt.packpath = { packpath }
	print("Packpath set to:", vim.inspect(vim.opt.packpath:get()))
end
