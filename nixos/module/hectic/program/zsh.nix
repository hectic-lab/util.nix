{
  inputs,
  flake,
  self,
}: {
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.hectic.program.zsh;
in {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  options.hectic.program.zsh.enable = lib.mkEnableOption "Enable hectic zsh config";

  config = lib.mkIf cfg.enable {
    # system-level zsh must be on for home-manager zsh to work
    programs.zsh.enable = true;
    users.defaultUserShell = pkgs.zsh;

    home-manager.users.root = {
      home.stateVersion = lib.mkDefault "25.05";

      programs.zsh = {
        enable               = true;
        enableCompletion     = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;

        history = {
          size = 10000;
          path = "$HOME/.zsh/.zsh_history";
        };

        oh-my-zsh = {
          enable = true;
          theme  = "terminalparty";
        };

        shellAliases = self.lib.sharedShellAliases;

        initContent = ''
          set -ovi
        '';
      };
    };
  };
}
