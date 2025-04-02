ifndef VERBOSE
.SILENT:
endif

.PHONY: gendocs stylua lua_ls-check lua_ls-debug

stylua:
	stylua --color always --check ./lua ./plugin

lua_ls-check:
	@echo "Running lua-language-server check for version: $(version)"
	if [ ! -f ci/.luarc.$(version).json ]; then \
		echo "Error: Configuration file .luarc.$(version).json not found."; \
		exit 1; \
	fi

	rm -rf .ci/lua_ls-log
	cat $(CURDIR)/ci/.luarc.$(version).json
	
	lua-language-server --configpath $(CURDIR)/ci/.luarc.$(version).json \
		--logpath .ci/lua_ls-log --check lua

	if [ ! -f .ci/lua_ls-log/check.json ]; then \
		echo "Error: check.json not found."; \
		exit 1; \
	fi

	# If file length is more than 2 characters (not just "[]"), print and exit
	if [ `wc -m < .ci/lua_ls-log/check.json` -gt 2 ]; then \
		echo "❌ Diagnostics found:"; \
		cat .ci/lua_ls-log/check.json; \
		exit 1; \
	else \
		echo "✅ No errors found."; \
	fi


CONFIG_FILE = $(shell realpath ci/.luarc.$(version).json)
lua_ls-debug:
	@echo "Running lua-language-server debug for version: $(version)"
	if [ ! -f ${CONFIG_FILE} ]; then \
		echo "Error: Configuration file $${CONFIG_FILE} not found."; \
		exit 1; \
	fi

	rm -rf .ci/lua_ls-log
	cat ${CONFIG_FILE}
	
	lua-language-server --configpath ${CONFIG_FILE}\
		--logpath .ci/lua_ls-log --check lua

	echo "Debug log outputs: "; \
	find .ci/lua_ls-log -type f -name "*.log" -exec cat {} \;

	echo "VIMRUNTIME Environment Variable: $${VIMRUNTIME}";

	echo "Absolute Runtime path: "; \
	realpath .ci/neovim/share/nvim/runtime; \
	echo "Absolute Treesitter runtime path: "; \
	realpath .ci/neovim/share/nvim/runtime/lua/vim/treesitter/query.lua;

	echo "Runtime path: "; \
	ls -la .ci/neovim/share/nvim/runtime; \
	echo "Treesitter runtime path: "; \
	ls -la .ci/neovim/share/nvim/runtime/lua/vim/treesitter; \
	echo "Treesitter query.lua: "; \
	head .ci/neovim/share/nvim/runtime/lua/vim/treesitter/query.lua; 

	if [ ! -f .ci/lua_ls-log/check.json ]; then \
		echo "Error: check.json not found."; \
		exit 1; \
	fi

	# If file length is more than 2 characters (not just "[]"), print and exit
	if [ `wc -m < .ci/lua_ls-log/check.json` -gt 2 ]; then \
		echo "❌ Diagnostics found:"; \
		cat .ci/lua_ls-log/check.json; \
		exit 1; \
	else \
		echo "✅ No errors found."; \
	fi

gendocs:
	@echo "Generating documentation..."
	nvim --headless -c 'luafile ci/mini-doc.lua' -c 'qa!'
	cat doc/introduction.header doc/ninjection.txt > doc/ninjection_final.txt
	mv doc/ninjection_final.txt doc/ninjection.txt
	@echo "Documentation generated in doc/ninjection.txt"
