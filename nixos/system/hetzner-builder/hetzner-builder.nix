{
  inputs,
  flake,
  self,
}: {
  lib,
  modulesPath,
  ...
}: {
  imports = [
    self.nixosModules.hectic
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.disko.nixosModules.disko
    # IPs injected at install time by deploy --via-hetzner via nixos-anywhere --extra-files.
    # The file sets hectic.hardware.hetzner-cloud.ipv4 and .ipv6.
    # During flake evaluation the file does not exist, so the import is skipped.
  ] ++ (if builtins.pathExists /etc/nixos/hetzner-ips.nix
        then [ /etc/nixos/hetzner-ips.nix ]
        else []);

  hectic.archetype.base.enable = true;

  hectic.hardware.hetzner-cloud = {
    enable                 = true;
    networkMatchConfigName = "enp1s0";
    # ipv4 and ipv6 are provided by /etc/nixos/hetzner-ips.nix at install time.
    # Placeholder values satisfy the type checker during flake evaluation.
    ipv4 = lib.mkDefault "0.0.0.0";
    ipv6 = lib.mkDefault "fe80:0:0:0";
  };

  # cpx62 and all current Hetzner Cloud servers boot via UEFI.
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.firewall.enable = lib.mkForce false;

  # Use all cores for building
  nix.settings = {
    max-jobs      = "auto";
    cores         = 0;
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

  # Ephemeral keypair injected at install time by nixos-anywhere --extra-files.
  # deploy (--via-hetzner) generates a fresh ed25519 key per session, writes the
  # public key to /root/.ssh/authorized_keys in the extra-files tree, and uses
  # the matching private key for all subsequent SSH/nixos-rebuild connections.
  # The key and the server are both destroyed on EXIT, so there is no long-term
  # exposure.
  users.users.root.openssh.authorizedKeys.keyFiles = [
    /root/.ssh/authorized_keys
  ];
}
