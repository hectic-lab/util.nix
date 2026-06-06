{
  flake,
  self,
  inputs,
}:
with builtins;
with inputs.nixpkgs.lib;
with self.lib;
let
  # Combine hectic modules into one
  hectic.imports = attrValues (
    readModulesRecursive' (flake + "/nixos/module/hectic") { inherit flake self inputs; }
  );
  # Read generic modules separately
  generic = readModulesRecursive'
    (flake + "/nixos/module/generic")
    { inherit flake self inputs; };
in generic // {
  inherit hectic;
  default = hectic;
}
