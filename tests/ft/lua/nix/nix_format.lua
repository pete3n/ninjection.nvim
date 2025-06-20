local injected_content_edit = -- nix
		[[
let
			flake = builtins.getFlake (toString ./.);
		in
			if builtins.isAttrs flake.outputs.devShells.x86_64-linux.default
  then builtins.attrNames flake.outputs.devShells.x86_64-linux.default
			else "LEAF"
	]]
print(injected_content_edit)
