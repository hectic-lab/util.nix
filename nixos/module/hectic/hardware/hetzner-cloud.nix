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
  options.hectic.hardware.hetzner-cloud.enable = lib.mkEnableOption "Enable hetzner-cloud hardware configurations";

  config = lib.mkIf cfg.enable {
    boot.loader.grub.device = "/dev/sda";
    boot.initrd.availableKernelModules = [
      "ata_piix"
      "uhci_hcd"
      "xen_blkfront"
    ] ++ (if pkgs.system != "aarch64-linux" then [ "vmw_pvscsi" ] else []);
    boot.initrd.kernelModules = ["nvme"];
    fileSystems."/" = {
      device = "/dev/sda1";
      fsType = "ext4";
    };
  };
}
