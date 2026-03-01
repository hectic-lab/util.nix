{
  inputs,
  flake,
  self,
}: {
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    self.nixosModules.hectic
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.disko.nixosModules.disko
  ];

  hectic.archetype.base.enable = true;

  # DHCP -- ephemeral server, no static IP needed
  networking = {
    useDHCP      = true;
    useNetworkd  = false;
    firewall.enable = lib.mkForce false;
  };

  # Use all cores for building
  nix.settings = {
    max-jobs = "auto";
    cores    = 0;
    # Allow the target host to use this machine as a builder
    trusted-users = [ "root" ];
  };

  # Generous zram so large closures (e.g. torchWithCuda) don't OOM
  zramSwap = {
    enable        = true;
    priority      = 100;
    algorithm     = lib.mkDefault "zstd";
    memoryPercent = lib.mkDefault 100;
    memoryMax     = null;
    swapDevices   = 1;
  };

  # Disk layout -- plain GPT on /dev/sda (standard Hetzner Cloud device)
  disko.devices.disk.main = {
    type   = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size     = "1M";
          type     = "EF02"; # BIOS boot
          priority = 1;
        };
        ESP = {
          size    = "512M";
          type    = "EF00";
          content = {
            type       = "filesystem";
            format     = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          size    = "100%";
          content = {
            type       = "filesystem";
            format     = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "xen_blkfront"
    "vmw_pvscsi"
  ];

  # Dedicated keypair for the ephemeral builder.
  # Private key lives at ~/.ssh/hetzner-builder on the operator's machine
  # (generated once: ssh-keygen -t ed25519 -f ~/.ssh/hetzner-builder -C hetzner-builder).
  # Only the public key is stored in the repo -- the builder is ephemeral and
  # always destroyed after use, so there is no long-term exposure.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICPGMqw0l8b46oiAmfyUWELIt6D9olH/rItLLjhw/LqG hetzner-builder"
  ];
}
