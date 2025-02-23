ifndef VERBOSE
.SILENT:
endif

luacheck:
	luacheck .

stylua:
	stylua --check .

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

lua_ls-debug:
	@echo "Running lua-language-server debug for version: $(version)"
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

	echo "Debug log outputs: "; \
	find .ci/lua_ls-log -type f -name "*.log" -exec cat {} \;
