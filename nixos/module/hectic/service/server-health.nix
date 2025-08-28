{ 
  inputs,
  flake,
  self,
}:
{ 
  pkgs,
  lib,
  config,
  ...
}: let
  system = pkgs.system;
  cfg = config.hectic.services.server-health;
  #   URLS="http://..."     # default: none
  #   VOLUMES="/ /home"     # default: all from df -P
in {
  options = {
    hectic.serivices.server-health = {
      enable   = lib.mkEnableOption "enable serverhelth services";
      urls = lib.mkOption {
        type = lib.types.port;
        default = "5899";
        description = ''
	  urls to check
        '';
      };
      volumes = lib.mkOption {
        type = lib.types.port;
        default = "5899";
        description = ''
          volumes to check
        '';
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = "5899";
        description = ''
          service's port
        '';
      };
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.services."hectic-server-health" = {
      description = "Hectic server health check";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${self.packages.${system}.server-health}/bin/server-health";
        Environment = (if cfg.urls != null then [
	  "URLS=${cfg.urls}"
	] else []) ++ (if cfg.volumes != null then [
	  "VOLUMES=${cfg.volumes}"
	] else []);
        Restart = "always";
        RestartSec = "5s";
        
        # Shutdown configuration
        TimeoutStopSec = "30s";
        KillSignal = "SIGTERM";
        KillMode = "mixed";
        
        # Security and process management
        RemainAfterExit = false;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
}
