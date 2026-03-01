{
  flake,
  self,
  inputs,
  system,
  ...
}: let
  name = builtins.baseNameOf ./.;

in self.lib.nixpkgs-lib.nixosSystem {
  pkgs = import inputs.nixpkgs {
    inherit system;
    overlays = [ self.overlays.default ];
  };
  modules = [
    { networking.hostName = name; }
    (import ./${name}.nix { inherit flake self inputs; })
  ];
}
