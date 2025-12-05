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
  # TODO:
  # white list
  # torent
  # rate limit
  # ping - game and speak
 
  imports = [
    self.nixosModules.hectic
    inputs.sops-nix.nixosModules.sops
    #./voice-tune.nix
    ./matrix.nix
  ];

  currentServer = {
    matrix = {
      postgresql   = {
        port = 5432;
        initialEnvFile = config.sops.secrets."init-postgresql".path;
      };
      matrixDomain   = "accord.tube";
    };
  };

  services.xray = {
    enable  = true;
    settingsFile = config.sops.secrets."config".path;
  };

  users.users.root.openssh.authorizedKeys.keys = [
    ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOn1KflaIX1RU9YS/qLb0GInmndYxx2vTLZC9OA+eXZl''
  ];

  boot.loader.grub.device =  "/dev/vda";
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "xen_blkfront"
  ] ++ (if pkgs.system != "aarch64-linux" then [ "vmw_pvscsi" ] else []);
  boot.initrd.kernelModules = ["nvme"];

  disko.devices = {
    disk.vda = {
      device = lib.mkDefault "/dev/vda";
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

  hectic = {
    archetype.base.enable = true;
    archetype.dev.enable  = true;
  };

  sops = {
    gnupg.sshKeyPaths         = [ ];
    age.sshKeyPaths           = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile           = ../../../sus/bfs.xray.yaml;

    secrets."config"          = {};
    secrets."init-postgresql" = {};
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      xrayPort
      80 443 # for acme
    ];
  };
}
