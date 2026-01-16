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
  cfg = config.hectic.hardware.zombro;
in {
  options.hectic.hardware.zombro = {
    enable = lib.mkEnableOption "Enable zombro hardware configurations";
    device = lib.mkOption {
      type = lib.types.str;
      default = "/dev/vda";
      example = "/dev/disk/by-uuid/f184a16b-6eca-41cb-b48a-ff37cdce1d79";
      description = ''
        boot device uuid 
        if it is null then will use "/dev/vda" 
        /dev/vda - default zombro device
        !! But can changes on reboot if server have volumes
        !! So use IDs
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge
  [
    {
      boot.loader.grub.device =  cfg.device;
      boot.initrd.availableKernelModules = [
        "ata_piix"
        "uhci_hcd"
        "xen_blkfront"
      ] ++ (if pkgs.system != "aarch64-linux" then [ "vmw_pvscsi" ] else []);
      boot.initrd.kernelModules = ["nvme"];

      disko.devices = {
        disk.master = {
          device = cfg.device;
          content = {
            type = "table";
            format = "msdos";
            partitions = [
              {
                name = "root";
                part-type = "primary";
                fs-type = "ext4";
                bootable = true;
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              }
            ];
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
