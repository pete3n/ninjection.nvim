vim.api.nvim_create_user_command("NJedit", require("ninjection").create_child_buffer, {})
vim.api.nvim_create_user_command("NJSyncChild", require("ninjection").sync_child, {})
vim.api.nvim_create_user_command("NJSelect", require("ninjection").select, {})

