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

  services.xray = {
    enable  = true;
    setting = ''
      {
        "inbounds": [
          {
            "port": 10086,
            "protocol": "vmess",
            "settings": {
              "clients": [
                {
                  "id": "b831381d-6324-4d53-ad4f-8cda48b30811"
                }
              ]
            }
          }
        ],
        "outbounds": [
          {
            "protocol": "freedom"
          }
        ]
      }
    '';
  };
 
  hectic = {
    archetype.base.enable = true;
    hardware.lenovo-legion.enable = true;
  };
}
