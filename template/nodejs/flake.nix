{
  description = "";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    util = {
      url = "github:hectic-lab/util.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = { self, nixpkgs, util }:
  let
    overlays = [ util.overlays.default ];
  in
  util.lib.forAllSystemsWithPkgs overlays ({ system, pkgs }:
    let
      lib = pkgs.lib;
    in
    {
      ### DEV SHELL ###
      devShells.${system} = {
	      default = import ./devshell/default.nix { inherit pkgs; };
      };
    }
  );
}
