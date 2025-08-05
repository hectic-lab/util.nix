{
  description = "";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    util = {
      url = "github:hectic-lab/util.nix?ref=fix/postgres-extension";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = { self, nixpkgs, rust-overlay, util }:
  let
    overlays = [ (import rust-overlay) util.overlays.default ];
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
