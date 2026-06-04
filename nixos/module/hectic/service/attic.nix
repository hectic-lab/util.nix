{ ... }: {
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.hectic.services.attic;
  environmentFile = "/var/lib/atticd/credentials.env";
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

  };

  config = lib.mkIf cfg.enable {
    systemd.services.atticd-credentials = {
      description = "Generate persistent atticd credentials";
      before      = [ "atticd.service" ];
      wantedBy    = [ "atticd.service" ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "atticd";
        UMask = "0077";
      };
      script = ''
        if [ -s ${environmentFile} ]; then
          exit 0
        fi

        install -m 0700 -d /var/lib/atticd
        secret="$(${lib.getExe pkgs.openssl} genrsa -traditional 4096 | ${pkgs.coreutils}/bin/base64 -w0)"
        cat > ${environmentFile} <<EOF
        ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="$secret"
        EOF
        chmod 0600 ${environmentFile}
      '';
    };

    services.atticd = {
      enable          = true;
      environmentFile = environmentFile;
      settings = {
        listen = "${cfg.listenAddress}:${toString cfg.port}";
        allowed-hosts = [ cfg.hostName ];
        api-endpoint = "https://${cfg.hostName}/";
        compression.type = "zstd";
      };
    };
  };
}
