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
  matrixDomain = "accord.tube";
in {
  imports = [
    self.nixosModules.hectic
    inputs.sops-nix.nixosModules.sops
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEJZFglwpPMFLnQDOqi84nlMFktZSSu1GzUIafvClUaD''
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "sd_mod"
  ];
  boot.initrd.kernelModules = ["nvme"];

  disko.devices = {
    disk.nvme0n1 = {
      device = lib.mkDefault "/dev/nvme0n1";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
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

  networking = {
    networkmanager.enable = true;
    useDHCP = lib.mkDefault true;
    interfaces.enp5s0.useDHCP = lib.mkDefault true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        80 443
      ];
    };
  };

  hardware.enableRedistributableFirmware = true;

  hectic = {
    archetype.base.enable = true;
    archetype.dev.enable  = true;
  };

  sops = {
    gnupg.sshKeyPaths         = [ ];
    age.sshKeyPaths           = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile           = ../../../sus/neuro.yaml;
  };
}
