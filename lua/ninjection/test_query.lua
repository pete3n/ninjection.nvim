local function mod_capture(text)
  local lines = vim.split(text, "\n", { plain = true })

  -- Remove the leading '' for a Nix injected language
	-- Remove entire line if the '' is by itself
  if lines[1] then
		-- Remove whitespace from beginning and end of line
    local trimmed = lines[1]:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "''" then
      table.remove(lines, 1)
			-- Adjust range appropriately
    else
      lines[1] = lines[1]:gsub("^%s*''%s*", "")
    end
  end

  -- Clean the last line
  if lines[#lines] then
    local line = lines[#lines]
    -- Remove trailing whitespace first
    local without_trailing = line:gsub("%s+$", "")
    -- Check if it ends exactly with ''
    if without_trailing:sub(-2) == "''" then
      -- Check if it *only* contains ''
      local without_spaces = without_trailing:gsub("%s+", "")
      if without_spaces == "''" then
        table.remove(lines, #lines)
				-- Adjust range appropriately
      else
        -- Strip the trailing ''
        lines[#lines] = line:gsub("%s*''%s*$", "")
      end
    end
  end

  return table.concat(lines, "\n")
end

local lang = "nix"
local bufnr = vim.api.nvim_get_current_buf()
vim.notify("Running Treesitter query")
-- Define your custom query string inline.
local query_string =
[[
			(
				(comment) @inj_lang .
				(indented_string_expression) @inj_text
			)
		]]

-- Parse the custom query for the specified language.
local ok, query = pcall(vim.treesitter.query.parse, lang, query_string)
if not ok then
  error("Error parsing custom query: " .. query)
end

-- Get the Treesitter parser for the current buffer and parse the syntax tree.
local parser = vim.treesitter.get_parser(bufnr, lang)
local tree = parser:parse()[1]
local root = tree:root()


-- Iterate over all captures and print capture name and text.
for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
  local cap_name = query.captures[id]
	if cap_name == "inj_lang" then
		local capture_text = vim.treesitter.get_node_text(node, bufnr)
		local inj_lang = capture_text:gsub("#%s*([%w%p]+)%s*", "%1")
		print(string.format("Capture Name: %s\n%s", cap_name, inj_lang))
	end

	if cap_name == "inj_text" then
		local inj_text = vim.treesitter.get_node_text(node, bufnr)
		local s_row, s_col, e_row, e_col = vim.treesitter.get_node_range(node)
		local cleaned_text = mod_capture(inj_text)
		print(string.format("Node Range: %s:%s - %s:%s Capture Name: %s\n%s", (s_row+1), s_col, (e_row+1), e_col, cap_name, cleaned_text))
	end
end

