/*
  ( indented_string_expression
  	(string_fragment) @string_fragment
  ) @quoted_inject

  (
      (indented_string_expression) @quoted_inject
      (#offset! @quoted_inject 0 6 0 -3)
  )

  (
  	((indented_string_expression) @quoted_inject (#offset! @quoted_inject 5 0 0 -5))
  ) @offset_inject

  (comment) @injection.language .
  (indented_string_expression) @injection.content
  (#gsub! @injection.language "#%s*([%w%p]+)%s*" "%1")
  (#offset! @injection.content 2 2 -1 0)
  (#set! injection.combined)
*/
{ pkgs, ... }:
{
  lua_test = # lua
    ''
      		local test = true
      		local var1 ="b"
      		local var2 ="c"
      		local var3 ="d"
      	'';

  extraConfigLuaPost = # lua
    ''
      if wk_available then
      	wk.add({
      		{ "<leader>p", group = "parsing", icon = " " },
      		{ "<leader>pp", group = "paramater swap", icon = "󰓡 " },
      		{ "<leader>pf", group = "function swap", icon = "󰓡 " },
      		{ "<leader>ppi", desc = "swap next inner parameter" },
      		{ "<leader>ppo", desc = "swap next outer parameter" },
      		{ "<leader>ppI", desc = "swap prev inner parameter" },
      		{ "<leader>ppO", desc = "swap prev outer parameter" },
      		{ "<leader>pfi", desc = "swap next inner function" },
      		{ "<leader>pfo", desc = "swap next outer function" },
      		{ "<leader>pfI", desc = "swap prev inner function" },
      		{ "<leader>pfO", desc = "swap prev outer function" },
      	})
      end
    '';

  extraSloppyLua = # lua
    ''
      			if wk_available then
      			wk.add({
      			{ "<leader>p", group = "parsing", icon = " " },
      			{ "<leader>pp", group = "paramater swap", icon = "󰓡 " },
      			{ "<leader>pf", group = "function swap", icon = "󰓡 " },
      			{ "<leader>ppi", desc = "swap next inner parameter" },
      			{ "<leader>ppo", desc = "swap next outer parameter" },
      			{ "<leader>ppI", desc = "swap prev inner parameter" },
      			{ "<leader>ppO", desc = "swap prev outer parameter" },
      			{ "<leader>pfi", desc = "swap next inner function" },
      			{ "<leader>pfo", desc = "swap next outer function" },
      			{ "<leader>pfI", desc = "swap prev inner function" },
      			{ "<leader>pfO", desc = "swap prev outer function" },
      			})
      			end
      	'';

  shellHook = # sh
    ''
			#! /usr/bin/env
			# symlink the .luarc.json generated in the overlay
			ln -fs ${pkgs.nvim-luarc-json} .luarc.json
			# allow quick iteration of lua configs
			ln -Tfns $PWD/ci/nix/kickstart-nix.nvim/nvim ~/.config/nvim-dev
			# Make packpath available for testing
			nvimDevPath=$(which nvim-dev)
			echo "nvim-dev path: $nvimDevPath"

			# Use sed to extract the value following "set packpath^=" and before the closing quote.
			PACKPATH_VALUE=$(sed -n 's/.*set packpath\^=\([^"]*\)".*/\1/p' "$nvimDevPath")
			RTP_VALUE=$(sed -n 's/.*set rtp\^=\([^"]*\)".*/\1/p' "$nvimDevPath")
			VIMRUNTIME=

			export NVIM_PACKPATH="$PACKPATH_VALUE"
			export NVIM_RTP="$RTP_VALUE"
			export VIMRUNTIME="${pkgs.nvim-dev}/share/nvim/runtime"
			echo "NVIM_PACKPATH set to: $NVIM_PACKPATH"
			echo "NVIM_RTP set to: $NVIM_RTP"
			echo "VIMRUNTIME set to: $VIMRUNTIME" '';

  c_code = # c
    ''
      			void main(argv *int argc *char) {
      				printf("Hello world\n");	
      			}

      			void fun(int x, int y) {
      				int z = (x + y);
      				printf("Z: %d", z);
      			}
      		'';
}
