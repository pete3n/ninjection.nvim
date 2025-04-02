{
  description = "Neovim derivation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    gen-luarc.url = "github:mrcjkb/nix-gen-luarc-json";

    # Add bleeding-edge plugins here.
    # They can be updated with `nix flake update` (make sure to commit the generated flake.lock)
    # wf-nvim = {
    #   url = "github:Cassin01/wf.nvim";
    #   flake = false;
    # };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    let
      systems = builtins.attrNames nixpkgs.legacyPackages;

      # This is where the Neovim derivation is built.
      neovim-overlay = import ./nix/neovim-overlay.nix { inherit inputs; };
    in
    flake-utils.lib.eachSystem systems (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            # Import the overlay, so that the final Neovim derivation(s) can be accessed via pkgs.<nvim-pkg>
            neovim-overlay
            # This adds a function can be used to generate a .luarc.json
            # containing the Neovim API all plugins in the workspace directory.
            # The generated file can be symlinked in the devShell's shellHook.
            inputs.gen-luarc.overlays.default
          ];
        };
        shell = pkgs.mkShell {
          name = "nvim-devShell";
          buildInputs = with pkgs; [
            lua-language-server
            nil
            stylua
            luajitPackages.luacheck
            luajitPackages.busted
            nvim-dev
          ];
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
							export NVIM_PACKPATH="$PACKPATH_VALUE"
              export NVIM_RTP="$RTP_VALUE"
              export VIMRUNTIME="${pkgs.nvim-dev}/share/nvim/runtime"
							export LUA_PATH="$PWD/lua/?.lua;$PWD/lua/?/init.lua;$PWD/plugin/?.lua;$PWD/plugin/?/init.lua;$LUA_PATH"
							echo "LUA_PATH set to: $LUA_PATH"
              echo "NVIM_PACKPATH set to: $NVIM_PACKPATH"
              echo "NVIM_RTP set to: $NVIM_RTP"
              echo "VIMRUNTIME set to: $VIMRUNTIME"
          '';
        };
      in
      {
        packages = {
          default = pkgs.nvim-dev;
          nvim = pkgs.nvim-pkg;
        };
        devShells = {
          default = shell;
        };
      }
    )
    // {
      # You can add this overlay to your NixOS configuration
      overlays.default = neovim-overlay;
    };
}
