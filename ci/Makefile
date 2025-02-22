ifndef VERBOSE
.SILENT:
endif

test: dependencies
	@echo "Running tests..."
	timeout 300 nvim -e \
		--headless \
		--noplugin \
		-u specs/spec.lua \
		-c "PlenaryBustedDirectory specs/features {minimal_init = 'specs/spec.lua'}"

luacheck:
	luacheck .

stylua:
	stylua --check .

lua-language-server: dependencies
	if [ ! -f ci/.luarc.$(version).json ]; then \
		echo "Error: Configuration file .luarc.$(version).json not found."; \
		exit 1; \
	fi

	rm -rf .ci/lua-language-server-log
	cat $(CURDIR)/ci/.luarc.$(version).json
	
	lua-language-server --configpath $(CURDIR)/ci/.luarc.$(version).json \
		--logpath .ci/lua-language-server-log --check lua

	if [ ! -f .ci/lua-language-server-log/check.json ]; then \
		echo "Error: check.json not found."; \
		exit 1; \
	fi

	ERROR_COUNT=`jq 'if type == "array" then length else 0 end' .ci/lua-language-server-log/check.json`

	if [ "$$ERROR_COUNT" -gt 0 ]; then \
		echo "Diagnostics found:"; \
		cat .ci/lua-language-server-log/check.json; \
		exit 1; \
	else \
		echo "No errors found."; \
	fi

dependencies:
	if [ ! -d .ci/vendor ]; then \
		git clone --depth 1 \
			https://github.com/nvim-lua/plenary.nvim \
			.ci/vendor/pack/vendor/start/plenary.nvim; \
	fi
