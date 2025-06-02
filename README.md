# ninjection.nvim

_This is another story about Pete_

_Pete loves Nix_ ❤️  <img src="assets/nix.png" alt="Icon" style="width: 16px; height: auto;">

_Pete likes to write Nix using Neovim_  <img src="assets/neovim.png" alt="Icon" style="width: 16px; height: auto;">

_This is what happens to Pete_:
- _Pete edits Nix files that contain injected languages._
- _Pete uses Treesitter which has Nix grammar for parsing. This make Pete happy_ 😊.
- _Neovim doesn't support attaching LSPs for different languages in the same buffer. This makes Pete sad_ 😢.
- _conform.nvim also doesn't recognize how to format injected languages. This makes Pete sad_ 😢,
_and sometimes angry_ 😠. 

_Don't be like Pete, use ninjection.nvim!_

## About Ninjection
Ninjection is a plugin designed to improve editing injected language text.
Its goal is to provide a seamless, first-class editing experience for injected
code with full support for LSPs, code-snippets, completions, formatting, etc.

Ninjection utilizes Treesitter's language parsing functionality to identify
nodes that contain an injected language, and appropriately designate that
language. It provides functions to create a new buffer for that language,
and to attach an appropriate LSP to that buffer.

While Ninjection was written primarily to edit injected languages in Nix files,
it should be easily extensible to other languages. Ninjection provides
configuration options to modify language parsing queries, LSP mappings,
window styles, and formatting.

### See it in action
[![Demo video](thumbnail.png)](https://github.com/user-attachments/assets/91386063-7040-44f2-b7a3-1cb8bede4fd3)

## Setup
### lazy.nvim
Simply add 'pete3n/ninjection.nvim' to your lazy.nvim setup function, such as:
```
require('lazy').setup({
    'pete3n/ninjection.nvim',
```

## Current Support
ninjection.nvim currently is limited to detecting injected languages in Nix 
files. However, it should be easily extensible for other languages. It expects 
injected languages to be designated with this format:
```
  injectedLang = # language_comment
    ''
      injected language content
      end
    '';
```

Both these limitations are derived from the Treesitter query which is used to
identify these code blocks. The default query for Nix is:
```
    (
        (comment) @injection.language
        .
        [
            (indented_string_expression
                (string_fragment) @injection.content)
            (string_expression
                (string_fragment) @injection.content)
        ]
        (#gsub! @injection.language "#%s*([%w%p]+)%s*" "%1")
        (#set! injection.combined)
    )
```

## Dependencies
Ninjection requires Neovim version 0.11.0 or greater, with
[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) and [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) both enabled.

You can verify these dependencies are met by running:
```
    :checkhealth ninjection
```
