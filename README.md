# ninjection.nvim

_This is another story about Pete_

_Pete loves Nix_ ❤️  <img src="assets/nix.png" alt="Icon" style="width: 16px; height: auto;">

_Pete likes to write Nix using Neovim_  <img src="assets/neovim.png" alt="Icon" style="width: 16px; height: auto;">

_This is what happens to Pete_:
- _Pete edits Nix files that contain injected languages._
- _Pete uses Treesitter which has Nix grammar for parsing. This make Pete happy 😊._
- _Neovim doesn't support attaching LSPs for different languages in the same buffer. This makes Pete sad 😢._
- _conform.nvim also doesn't recognize how to format injected languages. This makes Pete sad 😢, and sometimes angry 😠. 

_Don't be like Pete, use nininjection.nvim!_

## Current Support
ninjection.nvim currently is limited to detecting injected languages in Nix 
files. 
```
  extraPlugins = [
    (pkgs.vimUtils.buildVimPlugin {
      name = "ninjection.nvim";
      src = pkgs.fetchFromGitHub {
        owner = "pete3n";
        repo = "ninjection.nvim";
        rev = "44496fb3e706c795e87d475d674708919a01cbea";
        hash = "sha256-tSDIGbTD+5fm1Qo3922DGJ1YIRNAUJF2btWf4kWbCoM=";
      };
    })
  ];
```
This will register the NGUpdateRepo command which you can keybind.
If you call NGUpdateRepo with the cursor in a fetchFromGitHub attribute set, 
then it will check for the most recent revision, and if it is different from the
current, updates the revision and the corresponding hash.

## Dependencies
[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) must be installed.
jq, and nix-prefetch-git must be executable and available in your path. To confirm
dependencies are availabe, nix-prefetch includes a health check function that 
you can run from the nvim commandline with:
```
    :checkhealth nix-prefetch
```

## Future Development
- [x] fetchFromGitHub: update rev and hash
    - [ ] fetchFromGithub: preserve rev, update hash
    - [ ] sha256 attribute support
    - [ ] version tag interpretation/support
- [ ] fetchFromGitLab support
- [ ] fetchurl support 
- [ ] fetchzip support 
