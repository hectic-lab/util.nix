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
  cfg = config.hectic.hardware.cloudzy;
in {
  options.hectic.hardware.cloudzy = {
    enable = lib.mkEnableOption "Enable hetzner-cloud hardware configurations";
    ipGateway = lib.mkOption {
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
    prefixLength = lib.mkOption {
      type        = lib.types.int;
      example     = 24;
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
    networkMatchConfigName = lib.mkOption {
      type = lib.types.str;
      example = "enp1s0";
      description = ''
        type of network conection, 
	on older hetzner servers may be `ens3`
        on newer probably `enp1s0`

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

    disko.devices.disk.main = {
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
    networking.interfaces."30-wan" = {
      matchConfig.Name = cfg.networkMatchConfigName;
      ipv4.addresses = [
        { address = cfg.ipv4; prefixLength = cfg.prefixLength; }
      ];
    };
    networking.defaultGateway = cfg.ipGateway;
    networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

    boot.initrd.availableKernelModules = [
      "ata_piix"
      "uhci_hcd"
      "xen_blkfront"
    ] ++ (if pkgs.system != "aarch64-linux" then [ "vmw_pvscsi" ] else []);
  };
}
