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
  inherit (self.legacyPackages."${system}") pkgs;
  modules = [
    { networking.hostName = name; }
    (import ./${name}.nix { inherit flake self inputs; })
  ];
}
