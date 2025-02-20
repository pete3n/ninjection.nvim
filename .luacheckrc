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

files = {
	["lua/ninjection.lua"] = {
		ignore = {
			"631", -- allow line len > 120
		},
	},
}
