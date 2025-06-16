/*
(
	(interpolation
	 (select_expression
		 (variable_expression
			 (identifier) @name (#eq? @name "pkgs"))
		 ) @nix_pkgs
	) @nix_pkgs_expr
)
(
 (interpolation
	 (select_expression
		 (variable_expression
			 (identifier) @name (#eq? @name "lib"))
		 ) @nix_lib
	) @nix_lib_expr
)

  (interpolation
    (select_expression
      (variable_expression
				(identifier) @name  (#any-of? @name
					"lib"
					"pkgs")
      ) @nix_expr
    ) @nix_expr_group
  )

*/

shellHook = # sh
	''
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
            echo "VIMRUNTIME set to: $VIMRUNTIME"
						echo ${lib.test}
          '';

	bashScript = # bash
		''
	#! /usr/bin/env
	echo "Bash script"
	'';
