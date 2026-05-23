{
  flake,
  self,
  inputs,
  system,
  ...
}: let
  # Use folder name as name of this system; sanitize for hostName (no dots)
  name     = builtins.baseNameOf ./.;
  hostName = builtins.replaceStrings ["."] ["-"] name;

in self.lib.nixpkgs-lib.nixosSystem {
  pkgs = import inputs.nixpkgs {
    inherit system;
    overlays = [ self.overlays.default ];
  };
  modules = [
    { networking.hostName = hostName; }
    (import ./${name}.nix { inherit flake self inputs; })
  ];
}
