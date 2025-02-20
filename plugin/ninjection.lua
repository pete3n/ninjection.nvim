vim.api.nvim_create_user_command("NJEdit", require("ninjection").edit, {})
vim.api.nvim_create_user_command("NJReplace", require("ninjection").replace, {})
vim.api.nvim_create_user_command("NJSelect", require("ninjection").select, {})
