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
}: {
  # TODO:
  # white list
  # torent
  # rate limit
  # ping - game and speak

  imports = [
    self.nixosModules.xray-system
  ];

  hectic.generic.xray-system = {
    enable          = true;
    defaultSopsFile = ../../../sus/bfs.xray.yaml;
  };
}
