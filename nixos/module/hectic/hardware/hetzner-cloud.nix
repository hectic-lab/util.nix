{ 
  inputs,
  flake,
  self,
}:
{ 
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.hectic.hardware.hetzner-cloud;
in {
  options.hectic.hardware.hetzner-cloud = {
    enable = lib.mkEnableOption "Enable hetzner-cloud hardware configurations";
    #bootParUuid = lib.mkOption {
    #  type = with lib.types; nullOr oneOf [
    #    (lib.types.strMatching "^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$")
    #    (lib.types.strMatching "^[0-9a-fA-F-]{36}$")
    #  ];
    #  default = null;
    #  example = "5628-19B6";
    #  description = ''
    #    boot partition uuid if it is null 
    #    then will use "/dev/sda15" (default hetzner cloud boot device)
    #  '';
    #};
    ipv4 = lib.mkOption {
      type        = lib.types.strMatching "^([0-9]{1,3}\\.){3}[0-9]{1,3}$";
      example     = "188.243.124.246";
      description = ''
        
      '';
    };
    ipv6 = lib.mkOption {
      type        = lib.types.strMatching "^([0-9a-fA-F]{1,4}:){3}[0-9a-fA-F]{1,4}$";
      example     = "2a01:4f8:1c1a:d883";
      description = ''
        
      '';
    };
    device = lib.mkOption {
      type = lib.types.str;
      default = "/dev/sda";
      example = "/dev/disk/by-uuid/f184a16b-6eca-41cb-b48a-ff37cdce1d79";
      description = ''
        boot device uuid 
	if it is null then will use "/dev/sda" 
	/dev/sda - default hetzner cloud device
	!! But can changes on reboot if server have volumes
	!! So use IDs
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge
  [
    {
      boot.initrd.availableKernelModules = [
        "ata_piix"
        "uhci_hcd"
        "xen_blkfront"
      ] ++ (if pkgs.system != "aarch64-linux" then [ "vmw_pvscsi" ] else []);

      networking.useDHCP = lib.mkDefault true;
      systemd.network.enable = true;
      systemd.network.networks."30-wan" = {
        matchConfig.Name = "ens3";
        networkConfig.DHCP = "no";
        address = [
          "${cfg.ipv4}/32"
          "${cfg.ipv6}::/64"
        ];
        routes = [
          { Gateway = "172.31.1.1"; GatewayOnLink = true; }
          { Gateway = "fe80::1"; }
        ];
      };

      disko.devices = {
        disk = {
          main = {
            type = "disk";
            device = cfg.device;
            content = {
              type = "gpt";
              partitions = {
                boot = {
                  size = "1M";
                  type = "EF02";
                  priority = 1;
                };
                ESP = {
                  size = "512M";
                  type = "EF00";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                  };
                };
                root = {
                  size = "100%";
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/";
                  };
                };
              };
            };
          };
        };
      };
    } 
    (lib.mkIf (pkgs.system == "aarch64-linux") {
      boot.initrd.kernelModules = [ "virtio_gpu" ];
      boot.kernelParams = [ "console=tty" ];
    })
  ]);
}
