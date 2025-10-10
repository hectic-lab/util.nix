{
  flake,
  self,
  inputs,
  system,
  ...
}: let
  # Use folder name as name of this system
  name = builtins.baseNameOf ./.;

in self.lib.nixpkgs-lib.nixosSystem {
  pkgs = import inputs.nixpkgs-25-05 { 
    inherit system;
    overlays = [ self.overlays.default ];
  };
  modules = [
    { networking.hostName = name; }
    (import ./${name}.nix { inherit flake self inputs; })
  ];
}
