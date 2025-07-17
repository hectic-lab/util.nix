{
  flake,
  self,
  inputs,
  nixpkgs,
}:
with builtins;
with nixpkgs.lib;
with self.lib;
let
  # Combine hectic modules into one
  hectic.imports = attrValues (
    readModulesRecursive' ./hectic { inherit flake self inputs; }
  );
  # Read generic modules seperately
  generic = readModulesRecursive'
    ./generic
    { inherit flake self inputs; };
in generic // {
  inherit hectic;
  default = hectic;
}
