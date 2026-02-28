{ 
  inputs,
  flake,
  self,
}: {
  pkgs,
  modulesPath,
  lib,
  config,
  ...
}: let
  cfg = config.hectic.archetype.dev;
in {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  options.hectic.archetype.dev.enable = lib.mkEnableOption "Enable archetupe.dev";

  config = lib.mkIf cfg.enable {
    hectic.archetype.base.enable = true;
    hectic.program.zsh.enable    = true;
    hectic.program.nixvim.enable = true;

    services.getty.autologinUser = "root";

    virtualisation.vmVariant.virtualisation = {
      qemu.options = [
        "-nographic"
        "-display curses"
        "-append console=ttyS0"
        "-serial mon:stdio"
        "-vga qxl"
      ];
      forwardPorts = [
        {
          from = "host";
          host.port = 40500;
          guest.port = 22;
        }
      ];
    };

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
      };
    };

    environment = {
      systemPackages =
        (with pkgs; [
          curl
          neovim
          yq-go
          jq
          htop-vim
        ]);
    };

    # Adjust zsh prompt for dev archetype: show '#' instead of '%'
    home-manager.sharedModules = lib.mkAfter [
      {
        programs.zsh.initExtra = lib.mkAfter ''
          PROMPT="# %~ "
        '';
      }
    ];
  };
}
