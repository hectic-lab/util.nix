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
  cfg = config.hectic.services."sentinèlla";
  #   URLS="http://..."     # default: none
  #   VOLUMES="/ /home"     # default: all from df -P
in {
  options = {
    hectic.services."sentinèlla" = {
      probe = {
        enable   = lib.mkEnableOption "enable sentinèlla probe services, that provides endpoints for server status check";
        urls = lib.mkOption {
          type = lib.types.port;
          description = ''
            urls to check
          '';
        };
        authFile = lib.mkOption {
          type = lib.types.path;
	  example = ''
            config.sops.secrets."name-of-service/sentinèlla-probe".path
	  '';
	  description = ''
            file with lines: user:pass
	  '';
        };
        volumes = lib.mkOption {
          type = lib.types.port;
          description = ''
            volumes to check
          '';
        };
        port = lib.mkOption {
          type = lib.types.port;
          description = ''
            service's port
          '';
        };
        environmentPath = lib.mkOption {
          type = lib.types.path;
	  example = ''
            config.sops.secrets."name-of-service/environment".path
	  '';
	  description = ''
	    in case when you do not want show configurations in repository
	    ```
              VOLUMES=      # default: none
              URLS=         # default: all from df -P
              PORT=
              AUTH_FILE=    # lines:   user:pass
	    ```
	  '';
        };
      };
      sentinel = {
        enable   = lib.mkEnableOption "enable sentinèlla sentinel services, that reported servers statuses based on probe polls";
        environmentPath = lib.mkOption {
          type = lib.types.path;
	  example = ''
            config.sops.secrets."name-of-service/environment".path
	  '';
	  description = ''
	    in case when you do not want show configurations in repository
	  '';
        };
      };
    };
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.probe.enable {
      systemd.services."sentinèlla-probe" = {
        description = "Hectic server health check";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${self.packages.${system}."sentinèlla"}/bin/probe";
          EnvironmentFile = cfg.probe.environmentPath;
          Environment = (if cfg.probe.urls != null then [
            "URLS=${cfg.probe.urls}"
          ] else []) ++ (if cfg.probe.volumes != null then [
            "VOLUMES=${cfg.volumes}"
          ] else []) ++ (if cfg.probe.port != null then [
            "PORT=${builtins.toString cfg.probe.port}"
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
    })
    (lib.mkIf cfg.sentinel.enable {
      
    })
  ];
}
