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
  cfg = config.hectic.services.media-browser;

  mediaBrowserApp = pkgs.hectic.media-browser;
in {
  options.hectic.services.media-browser = {
    enable = lib.mkEnableOption "Matrix media browser web app";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port to bind the media browser web server.";
    };

    mediaStorePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/matrix-synapse/media_store";
      description = "Path to Synapse media store.";
    };

    s3CredentialsFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to S3 credentials file (ACCESS_KEY_ID=..., SECRET_ACCESS_KEY=...).";
    };

    s3Bucket = lib.mkOption {
      type = lib.types.str;
      description = "S3 bucket name.";
    };

    s3Endpoint = lib.mkOption {
      type = lib.types.str;
      description = "S3 endpoint URL.";
    };

    s3Region = lib.mkOption {
      type = lib.types.str;
      default = "hel1";
      description = "S3 region name.";
    };

    s3Prefix = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "S3 object key prefix.";
    };

    dbName = lib.mkOption {
      type = lib.types.str;
      default = "matrix-synapse";
      description = "PostgreSQL database name.";
    };

    dbUser = lib.mkOption {
      type = lib.types.str;
      default = "matrix-synapse";
      description = "PostgreSQL database user.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.media-browser = {
      description = "Matrix Media Browser";
      after = [ "network.target" "postgresql.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "matrix-synapse";
        Group = "matrix-synapse";
        ExecStart = "${mediaBrowserApp}/bin/media-browser-wrapped";
        Restart = "on-failure";
        RestartSec = 5;
      };
      environment = {
        FLASK_ENV = "production";
        PORT = toString cfg.port;
        MEDIA_STORE_PATH = cfg.mediaStorePath;
        S3_BUCKET = cfg.s3Bucket;
        S3_ENDPOINT = cfg.s3Endpoint;
        S3_REGION = cfg.s3Region;
        S3_PREFIX = cfg.s3Prefix;
        DB_NAME = cfg.dbName;
        DB_USER = cfg.dbUser;
        DB_HOST = "/run/postgresql";
        DB_PORT = "5432";
      };
      serviceConfig.EnvironmentFile = cfg.s3CredentialsFile;
    };
  };
}
