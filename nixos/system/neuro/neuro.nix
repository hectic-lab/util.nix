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
}: let system = pkgs.stdenv.hostPlatform.system; in {
  imports = [
    self.nixosModules.hectic
    inputs.sops-nix.nixosModules.sops
    ./minecraft.nix
    ./hardware.nix 
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIETMumAHP+htbRvbrmzVoeesbT0+WcH1Wz8htk+7Ik+6"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEJZFglwpPMFLnQDOqi84nlMFktZSSu1GzUIafvClUaD"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGj7u/JuY9RwjoxnmO2b+pwC8XbMn+QOy44UpuN0Y1do riquizu"
  ];

  # disko.devices = {
  #   disk.master = {
  #     device = lib.mkDefault "/dev/disk/by-id/nvme-eui.00000000000000000026b7686dfafe35";
  #     type = "disk";
  #     content = {
  #       type = "gpt";
  #       partitions = {
  #         ESP = {
  #           size = "1G";
  #           type = "EF00";
  #           content = {
  #             type = "filesystem";
  #             format = "vfat";
  #             mountpoint = "/boot";
  #           };
  #         };
  #         root = {
  #           size = "100%";
  #           content = {
  #             type = "filesystem";
  #             format = "ext4";
  #             mountpoint = "/";
  #           };
  #         };
  #       };
  #     };
  #   };
  # };

  networking = {
    networkmanager.enable = true;
    useDHCP = lib.mkDefault true;
    interfaces.enp6s0 = {
      useDHCP = lib.mkDefault true;
      wakeOnLan.enable = true;
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [
        80 443 # HTTP, HTTPS
      ];
      allowedUDPPorts = [ 9 ]; # Wake on LAN
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

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" "sr_mod" "ext4" ];
  boot.initrd.kernelModules = [ "nvme" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-label/NIXROOT";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-label/NIXBOOT";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware = {
    cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };

  swapDevices = [ ];

  programs.tmux.enable = true;

  zramSwap.enable        = true;
  zramSwap.priority      = 100;
  zramSwap.memoryMax     = null;
  zramSwap.algorithm     = lib.mkDefault "zstd";
  zramSwap.swapDevices   = 1;
  zramSwap.memoryPercent = lib.mkDefault 100;

  environment.systemPackages = with pkgs; let
    python-ai = python3.withPackages (ps: let
      torchCuda     = ps.torchWithCuda;
      torchvision   = ps.torchvision.override { torch = torchCuda; };
      pytorch3dCuda = ps.pytorch3d.override { torch = torchCuda; };
    in [
      torchCuda
      torchvision
      pytorch3dCuda
      ps.fvcore
      ps.iopath
      ps.tqdm
      hectic.py3-openai-shap-e  # Uncomment when needed; depends on torch
    ]);
  in [
    python-ai
    git
    neovim
    wget
    ethtool
    rsync
    # docker
  ];
}
