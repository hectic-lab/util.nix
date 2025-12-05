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
  cfg = config.hectic.hardware.geo-hosting;
in {
  options.hectic.hardware.geo-hosting = {
    enable = lib.mkEnableOption "Enable geo-hosting hardware configurations";
    ipv4Gateway = lib.mkOption {
      type        = lib.types.strMatching "^([0-9]{1,3}\\.){3}[0-9]{1,3}$";
      example     = "188.243.124.1";
      description = ''
        
      '';
    };
    ipv4 = lib.mkOption {
      type        = lib.types.strMatching "^([0-9]{1,3}\\.){3}[0-9]{1,3}$";
      example     = "188.243.124.246";
      description = ''
        
      '';
    };
    device = lib.mkOption {
      type = lib.types.str;
      default = "/dev/vda";
      example = "/dev/disk/by-uuid/f184a16b-6eca-41cb-b48a-ff37cdce1d79";
      description = ''
        boot device uuid 
        if it is null then will use "/dev/vda" 
        /dev/sva - default geo hosting device
        !! But can changes on reboot if server have volumes
        !! So use IDs
      '';
    };
    networkMatchConfigName = lib.mkOption {
      type = lib.types.strMatching "^(enp1s0|ens3)$";
      example = "ens3";
      description = ''
        type of network conection

        you can use `networkctl list` on server to know it
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.loader.systemd-boot.enable = false;
    boot.loader.efi.canTouchEfiVariables = false;
    
    boot.loader.grub = {
      enable = true;
      device = cfg.device;
      efiSupport = false;
      forceInstall = true;
    };

    disko.devices.disk.vda = {
      device = cfg.device;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
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


    networking.useDHCP = false;
    networking.interfaces.${cfg.networkMatchConfigName} = {
      ipv4.addresses = [
        { address = cfg.ipv4; prefixLength = 24; }
      ];
    };
    networking.defaultGateway = cfg.ipv4Gateway;
    networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
  };
}
