{
  system,
  self,
  pkgs
}: {
  hemar      = import ./hemar.nix      { inherit self system pkgs; };
}
