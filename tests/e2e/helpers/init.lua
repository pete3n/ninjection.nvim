local packpath = vim.env.NVIM_PACKPATH
local rtp = vim.env.NVIM_RTP
local vimruntime = vim.env.VIMRUNTIME

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

for name, config in pairs(lspconfig) do
	if type(config) == "table" and config.cmd then
		table.insert(servers, {
			name = name,
			cmd = config.cmd,
		})
	end
end

-- Ensure the debug directory exists
vim.fn.mkdir("debug", "p")

local f, err = io.open("debug/debug_log.txt", "a")
if not f then
  print("Failed to open debug log file:", err)
else
  f:write("[LSPConfig Dump] Registered servers:\n")
  for _, server in ipairs(servers) do
    f:write(string.format("- %s → cmd: %s\n", server.name, vim.inspect(server.cmd)))
  end
  f:write("\n")
  f:close()
end

