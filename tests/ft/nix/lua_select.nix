{ }:
{
  injected_content_select = # lua
    ''
      local lua_content
      local more_lua_content
      for i = 1, 10, 1 do
        lua_content = lua_content + 1
      end
    '';
}
