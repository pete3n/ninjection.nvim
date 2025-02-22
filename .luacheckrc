-- Rerun tests only if their modification time changed.
cache = true

std = luajit
codes = true

self = false

-- Warning ref: https://luacheck.readthedocs.io/en/stable/warnings.html
ignore = {}

globals = {
	"_",
}

-- Global objects defined by the C code
read_globals = {
	"vim",
}

-- Ignore line length in type annotations because they cannot be multi-line
files = {
	["lua/ninjection/types.lua"] = {
		ignore = { "631" }
	},
	["lua/ninjection/dep_types.lua"] = {
		ignore = { "631" }
	}
}
