{
  flake,
  self,
  inputs,
  system,
  ...
}: let
  inherit (self.legacyPackages."${system}") pkgs;

  # Use folder name as name of this system
  name = builtins.baseNameOf ./.;

in pkgs.lib.nixosSystem {
  inherit pkgs;
  modules = [
    { networking.hostName = name; }
    (import ./${name}.nix { inherit flake self inputs; })
  ];
}
