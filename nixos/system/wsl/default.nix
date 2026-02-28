{
  flake,
  self,
  inputs,
  system,
  ...
}: let
  # Use folder name as system name
  name = builtins.baseNameOf ./.;

in self.lib.nixpkgs-lib.nixosSystem {
  pkgs = import inputs.nixpkgs {
    inherit system;
    overlays = [ self.overlays.default ];
    config.allowUnfree = true;
  };
  modules = [
    { networking.hostName = name; }
    inputs.nixos-wsl.nixosModules.default
    { wsl.enable = true; }
    (import ./${name}.nix { inherit flake self inputs; })
  ];
}
