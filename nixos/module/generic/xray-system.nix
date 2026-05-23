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
  cfg = config.hectic.generic.xray-system;
  xrayPort = 10086;
in {
  imports = [
    self.nixosModules.hectic
    inputs.sops-nix.nixosModules.sops
  ];

  options.hectic.generic.xray-system = {
    enable = lib.mkEnableOption "generic xray VPN server system configuration";

    defaultSopsFile = lib.mkOption {
      type        = lib.types.path;
      description = ''
        SOPS-encrypted secrets file used as `sops.defaultSopsFile`.
        Must define the `config` and `init-postgresql` secrets.
      '';
      example     = lib.literalExpression "../../../sus/bfs.xray.yaml";
    };
  };

  config = lib.mkIf cfg.enable {
    services.xray = {
      enable       = true;
      settingsFile = config.sops.secrets."config".path;
    };

    users.users.root.openssh.authorizedKeys.keys = [
      ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOn1KflaIX1RU9YS/qLb0GInmndYxx2vTLZC9OA+eXZl''
      ''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKPbIJATVyAw7F7vBZbHkCODXFo5gvDyqhuU0gnNUNH''
    ];

    boot.initrd.availableKernelModules = [
      "ata_piix"
      "uhci_hcd"
      "xen_blkfront"
    ] ++ (if pkgs.stdenv.hostPlatform.system != "aarch64-linux" then [ "vmw_pvscsi" ] else []);
    boot.initrd.kernelModules = ["nvme"];

    disko.devices = {
      disk.vda = {
        device  = lib.mkDefault "/dev/vda";
        content = {
          type       = "gpt";
          partitions = {
            boot = {
              size     = "1M";
              type     = "EF02";
              priority = 1;
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
    };

    hectic = {
      archetype.base.enable = true;
      archetype.dev.enable  = true;
    };

    sops = {
      gnupg.sshKeyPaths = [ ];
      age.sshKeyPaths   = [ "/etc/ssh/ssh_host_ed25519_key" ];
      defaultSopsFile   = cfg.defaultSopsFile;

      secrets."config"          = {};
      secrets."init-postgresql" = {};
    };

    networking.firewall = {
      enable          = true;
      allowedTCPPorts = [
        xrayPort 8443
        80 443 # for acme
      ];
    };

    environment.systemPackages = with pkgs; [
      xray
    ];
  };
}
