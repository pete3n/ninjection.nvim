if vim.g.did_load_treesitter_plugin then
  return
end
vim.g.did_load_treesitter_plugin = true

-- Grammars are installed by Nix (withAllGrammars), no runtime setup needed.
-- Guarded: start() throws on a buffer whose language can't be determined
-- (e.g. the empty [No Name] buffer during headless startup).
pcall(vim.treesitter.start)
vim.g.skip_ts_context_comment_string_module = true

-- TODO(treesitter): nvim-treesitter "main" (the version pinned in nixpkgs)
-- removed the `require('nvim-treesitter.configs').setup{}` API. The previous
-- textobjects / swap / move config (af, if, ]m, <leader>a, ...) lived here and
-- is gone — it never actually loaded (the bare vim.treesitter.start() above
-- aborted this chunk, and the API no longer exists). Reimplement those motions
-- with nvim-treesitter-textobjects' new-API setup if they're wanted.

require('treesitter-context').setup {
  max_lines = 3,
}

require('ts_context_commentstring').setup()

-- Tree-sitter based folding (new-API expression; enable via foldmethod=expr)
-- vim.opt.foldmethod = 'expr'
vim.opt.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
