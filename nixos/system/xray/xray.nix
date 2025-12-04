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
}: let
  xrayPort = 10086;
in {
  imports = [
    self.nixosModules.hectic
  ];

  services.xray = {
    enable  = true;
    settings = {
      "inbounds" = [
        {
          "port" = xrayPort;
          "protocol" = "vmess";
          "settings" = {
            "clients" = [
              {
                "id" = "04ad600a-0e94-4ba6-af93-74e03fd3f58d";
              }
            ];
          };
        }
      ];
      "log" = {
        "loglevel" = "warning";
      };
      "outbounds" = [
        {
          "protocol" = "freedom";
        }
      ];
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPPChQvpyOrPjRjp8pS5Yw+oJVmywDzefzZCXh1d44EY''
    ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGP3HjFoJNGHqHoEw9XLzh766QWknfaN07GGi8lsC2Tv''
  ];

 
  hectic = {
    archetype.base.enable = true;
    archetype.dev.enable  = true;
    hardware.hetzner-cloud = {
      enable                 = true;
      networkMatchConfigName = "enp1s0";
      ipv4                   = "77.42.45.173";
      ipv6                   = "2a01:4f9:c013:7230";
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      xrayPort
    ];
  };
}
