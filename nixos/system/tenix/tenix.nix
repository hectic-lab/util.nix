{
  inputs,
  self,
  ...
}: {
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.sops-nix.nixosModules.sops
    self.nixosModules.hectic
  ];

  hectic = {
    archetype.dev.enable = true;
    hardware.hetzner-cloud = {
      enable                 = true;
      device                 = "/dev/sda";
      networkMatchConfigName = "eth0";
      ipv4                   = "46.225.237.218";
      ipv6                   = "2a01:4f8:c2c:3b14";
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKAaObjLBslsdTlqEcYaS1TqX4x9aVJu75y27/8MFevO''
  ];

  environment.systemPackages = with pkgs; [
    git
    rsync
  ];
}
