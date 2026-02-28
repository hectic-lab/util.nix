{ 
  self,
  inputs,
  ...
}:
{
  config,
  pkgs,
  lib,
  ...
}: let
  name = "yukkop";
  #name = builtins.baseNameOf ./.;
  home = "/home/${name}";
  cfg = config.hectic.user.yukkop;
in {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  options.hectic.user.yukkop.enable = lib.mkEnableOption "Enable user.yukkop";

  config = lib.mkIf cfg.enable {
    users.users.${name} = {
      isNormalUser    = true;
      initialPassword = "kk";
      extraGroups     = [ "wheel" "docker" "owner" ];
    };

    home-manager.users.${name} = {
      home.stateVersion = "24.05";

      home.packages = with pkgs; [
        pinentry-tty
      ];

      programs.password-store = {
        enable = true;
        package = (pkgs.pass.override {
          x11Support     = false;
          waylandSupport = false;
          dmenuSupport   = false;
        }).withExtensions (exts: with exts; [
          pass-otp
        ]);
        settings.PASSWORD_STORE_DIR = "${home}/.pass";
      };

      programs.gpg = {
        enable  = true;
        homedir = "${home}/.gnupg";
      };

      services.gpg-agent = {
        enable              = true;
        pinentryPackage     = pkgs.pinentry-tty;
        enableZshIntegration = true;
        defaultCacheTtl     = 60 * 60;
        maxCacheTtl         = 60 * 60 * 24;
      };

      programs.bash.shellAliases = {
        dev = "nix develop -c zsh";
        # system-specific rebuild aliases can be added per-system
      };

      programs.git = {
        enable     = true;
        lfs.enable = true;
        userName   = "yukkop";
        userEmail  = "hectic.yukkop@gmail.com";
        extraConfig = {
          push.autoSetupRemote = true;
          init.defaultBranch   = "master";
        };
      };
    };
  };
}
