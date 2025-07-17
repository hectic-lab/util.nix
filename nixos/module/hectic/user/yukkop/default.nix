{
  self,
  inputs,
  flake,
  system ? "x86_64-linux",
  ...
}: let
  # Use folder name as name of this system
  name = builtins.baseNameOf ./.;
in inputs.home-manager.lib.homeManagerConfiguration {
  pkgs = self.legacyPackages."${system}";
  modules = [
    (import ./${name}.nix { inherit flake self inputs; })
  ];
}
