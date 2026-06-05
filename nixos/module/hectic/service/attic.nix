{ ... }: {
  lib,
  config,
  ...
}: let
  cfg = config.hectic.services.attic;
in {
  options.hectic.services.attic = {
    enable = lib.mkEnableOption "Attic binary cache server";

    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Public hostname used by clients to reach this Attic server.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Local address atticd binds to behind the reverse proxy.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Local port atticd binds to behind the reverse proxy.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        SOPS-backed environment file containing Attic JWT and object-storage
        credentials.
      '';
    };

    storage = {
      bucket = lib.mkOption {
        type = lib.types.str;
        description = "Hetzner Object Storage bucket name used by Attic.";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        description = "S3-compatible HTTPS endpoint for Hetzner Object Storage.";
      };

      region = lib.mkOption {
        type = lib.types.str;
        description = "Region name for Hetzner Object Storage.";
      };
    };

  };

  config = lib.mkIf cfg.enable {
    services.atticd = {
      enable          = true;
      environmentFile = cfg.environmentFile;
      settings = {
        listen = "${cfg.listenAddress}:${toString cfg.port}";
        allowed-hosts = [ cfg.hostName ];
        api-endpoint = "https://${cfg.hostName}/";
        compression.type = "zstd";
        storage = {
          type     = "s3";
          bucket   = cfg.storage.bucket;
          endpoint = cfg.storage.endpoint;
          region   = cfg.storage.region;
        };
      };
    };
  };
}
