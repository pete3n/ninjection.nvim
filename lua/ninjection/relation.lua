local M = {}

--- Add an injection buffer record.
--- @param parent_bufnr number: The parent buffer number.
--- @param child_bufnr number: The child (injected) buffer number.
--- @param inj_range table: The injection block's range data.
---     For example: { s_row = <number>, s_col = <number>, e_row = <number>, e_col = <number> }
---     s_row / s_col are the starting row and column, and e_row / e_col are corresponding ends
---     (These coordinates are in display (1-indexed) values.)
--- @param parent_cursor table: The parent's cursor position, e.g. { row = <number>, col = <number> }
---     (Display coordinates, 1-indexed.)
--- @param parent_mode string: The parent's mode ("n" for normal, "i" for insert, "v" for visual).
--- @return number: The assigned injection number (injnr), 1-indexed.
M.add_inj_buff = function(parent_bufnr, child_bufnr, inj_range, parent_cursor, parent_mode)
  assert(inj_range, "inj_range must be provided for add_injection_buffer (block range required)")
  assert(parent_cursor, "parent_cursor must be provided for add_injection_buffer")
  assert(parent_mode, "parent_mode must be provided for add_injection_buffer")

  if not M[parent_bufnr] then
    M[parent_bufnr] = { next_inj = 1, children = {} }
  end
  local injnr = M[parent_bufnr].next_inj

  -- Record the child buffer number, the injection range, and the parent's cursor and mode.
  inj_range.child_bufnr = child_bufnr
  inj_range.injnr = injnr
  inj_range.parent_cursor = parent_cursor  -- e.g., { row = 34, col = 15 }
  inj_range.parent_mode = parent_mode          -- e.g., "n", "i", or "v"
  M[parent_bufnr].children[injnr] = inj_range
  M[parent_bufnr].next_inj = injnr + 1

  return injnr
end

--- Retrieve injection information for a given parent buffer and injection number.
--- @param parent_bufnr number: The parent buffer number.
--- @param injnr number: The injection number (1-indexed).
--- @return table|nil: The injection range table (with parent_cursor and parent_mode), or nil if not found.
M.get_inj_buff = function(parent_bufnr, injnr)
  if M[parent_bufnr] and M[parent_bufnr].children[injnr] then
    return M[parent_bufnr].children[injnr]
  end
  return nil
end

--- Remove an injection buffer record.
--- @param parent_bufnr number: The parent buffer number.
--- @param injnr number: The injection number to remove.
M.rm_inj_buff = function(parent_bufnr, injnr)
  if M[parent_bufnr] then
    M[parent_bufnr].children[injnr] = nil
  end
end

--- List all injection records for a given parent buffer.
--- @param parent_bufnr number: The parent buffer number.
--- @return table: The table of injection records (keys are injnr).
M.ls_inj_buffers = function(parent_bufnr)
  if M[parent_bufnr] then
    return M[parent_bufnr].children
  end
  return {}
end

--- Debug helper: Print the entire injection table.
M.print_inj_table = function()
  print(vim.inspect(M))
end

vim.api.nvim_create_user_command("PrintInjectionTracker", function()
  M.print_inj_table()
end, {})

return M
