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
    device = lib.mkOption {
      type = lib.types.str;
      default = "/dev/sda/";
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

  config = lib.mkIf cfg.enable {
    boot.loader.grub.device = cfg.device;
    boot.initrd.availableKernelModules = [
      "ata_piix"
      "uhci_hcd"
      "xen_blkfront"
    ] ++ (if pkgs.system != "aarch64-linux" then [ "vmw_pvscsi" ] else []);
    boot.initrd.kernelModules = ["nvme"];

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
  };
}
