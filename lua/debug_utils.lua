local debug_file = io.open("debug/debug_log.txt", "a")

local M = {}

function M.log(msg)
  if debug_file then
    debug_file:write(msg .. "\n")
    debug_file:flush() -- force write to disk
  end
end

function M.close()
  if debug_file then
    debug_file:flush()
    debug_file:close()
    debug_file = nil
  end
end

return M
