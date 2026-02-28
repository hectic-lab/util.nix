{ inputs, flake, self }:
{ config, pkgs, lib, ... }: let
  cfg = config.hectic.services.support-bot;
  system = pkgs.stdenv.hostPlatform.system;

  packagesAttr = lib.mapAttrs (packageName: packageConfig: 
    packageConfig // {
      name = packageName;
    }) cfg;
  packagesArr = builtins.attrValues packagesAttr;
in {
  options = {
    hectic.services.support-bot = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            redisHost = lib.mkOption {
              type = lib.types.str;
	      default = "localhost";
	      example = "localhost";
	      description = ''
	        redis db host
		if localhost - module spawns redis 
	      '';
            };
            redisPort = lib.mkOption {
              type = lib.types.port;
	      example = "42069";
	      description = ''redis db port'';
            };
	    redisDb = lib.mkOption {
              type = lib.types.int;
	      apply = x: if x >= 0 && x <= 15 then x else throw "must be 0..15";
	      default = 0;
	      example = "0";
	      description = ''redis db number (0-15)'';
            };
            environmentPath = lib.mkOption {
              type = lib.types.path;
	      example = ''
                config.sops.secrets."name-of-service/environment".path
	      '';
	      description = ''
                BOT_TOKEN=
                BOT_DEV_ID=
                BOT_GROUP_ID=
                BOT_EMOJI_ID=
	      '';
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression /* nix */ ''
        {
          "name-of-service" = {
            environmentPath = config.sops.secrets."name-of-service/environment".path;
	    redisDb = 3;
            redisPort = 42069;
	    redisHost = localhost;
	  };
        };
      '';
      description = "Declarative support bot config";
    };
  };
  config = {
    services.redis.servers = lib.mkMerge (map (supportConfig: {
      "support-bot-${supportConfig.name}" = lib.mkIf (supportConfig.redisHost == "localhost") {
        enable = true;
        port = supportConfig.redisPort;
      };
    }) packagesArr);
    systemd.services = lib.mkMerge (map (supportConfig: {
      "support-bot-${supportConfig.name}" = {
        description = "Support Bot Service";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${self.packages.${system}.support-bot}/bin/support-bot";
          Restart = "always";
          RestartSec = "5s";
	  EnvironmentFile = supportConfig.environmentPath;
	  Environment = [
	    "REDIS_HOST=${supportConfig.redisHost}"
            "REDIS_PORT=${builtins.toString supportConfig.redisPort}"
            "REDIS_DB=${builtins.toString supportConfig.redisDb}"
	  ];
          
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
    }) packagesArr);
  };
}
