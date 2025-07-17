{
  inputs,
  flake,
  self,
}: {
  lib,
  pkgs,
  modulesPath,
  config,
  ...
}:
{
  imports = [
    self.nixosModules.hectic
  ];
 
  hectic = {
    archetype.base.enable = true;
    hardware.lenovo-legion.enable = true;
  };
}
