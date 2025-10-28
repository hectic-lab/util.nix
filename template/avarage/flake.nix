{
  description = "";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    hutil = {
      url = "github:hectic-lab/util.nix?ref=fix/postgres-extension";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = { self, nixpkgs, hutil }:
  let
    overlays = [ hutil.overlays.default ];
  in
  hutil.lib.forAllSystemsWithPkgs overlays ({ system, pkgs }:
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
