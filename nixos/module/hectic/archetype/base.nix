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
  cfg = config.hectic.archetype.base;
in {
  options.hectic.archetype.base.enable = lib.mkEnableOption "Enable archetupe.dev";

  config = lib.mkIf cfg.enable {
    programs.zsh.shellAliases = self.lib.sharedShellAliases;
    programs.zsh.enable = true;
    users.defaultUserShell = pkgs.zsh;

    # Enable flakes and new 'nix' command
    nix.settings.experimental-features = "nix-command flakes";

    networking.firewall.enable = true;

    environment = {
      defaultPackages = [];
      systemPackages = (with self.packages.${pkgs.system}; [
        nvim-pager
      ]);
      variables = {
        PAGER = with self.packages.${pkgs.system}; "${nvim-pager}/bin/pager";
      };
    };

    system.stateVersion = "25.05";
  };
}
