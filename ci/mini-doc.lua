require("mini.doc").setup({
	hooks = {
		block_pre = function(block)
			-- Mark the block if any section has nodoc
			for _, section in ipairs(block) do
				if section.info.id == "@nodoc" then
					block.info.nodoc = true
					break
				end
			end
		end,
		block_post = function(block)
			-- Clear the block if marked for nodoc.
			if block.info.nodoc then
				block:clear_lines()
			end
		end,
	},
})

local input_files = {
	"plugin/ninjection.lua",
	"lua/ninjection.init.lua",
	"lua/ninjection/config.lua",
	"lua/ninjection/types.lua",
	"lua/ninjection/health.lua",
	"lua/ninjection/parse.lua",
	"lua/ninjection/buffer.lua",
}
require("mini.doc").generate(input_files, "doc/ninjection.txt")
