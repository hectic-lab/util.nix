{ ... }: {
  lib,
  config,
  ...
}: let
  cfg = config.hectic.services.ente;

  webHostNames = [
    cfg.domains.accounts
    cfg.domains.cast
    cfg.domains.photos
  ];
in {
  options.hectic.services.ente = {
    enable = lib.mkEnableOption "Ente Photos self-hosted service";

    apiDomain = lib.mkOption {
      type = lib.types.str;
      description = "Public hostname for the Ente Museum API.";
    };

    domains = {
      accounts = lib.mkOption {
        type = lib.types.str;
        description = "Public hostname for the Ente accounts web app.";
      };

      cast = lib.mkOption {
        type = lib.types.str;
        description = "Public hostname for the Ente cast web app.";
      };

      albums = lib.mkOption {
        type = lib.types.str;
        description = "Public hostname for public Ente album links.";
      };

      photos = lib.mkOption {
        type = lib.types.str;
        description = "Public hostname for the Ente Photos web app.";
      };
    };

    maxUploadSize = lib.mkOption {
      type = lib.types.str;
      default = "10G";
      description = "Maximum request body accepted by nginx in front of Museum.";
    };

    disableRegistration = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether Museum should reject new account registration.";
    };

    smtp = {
      enable = lib.mkEnableOption "SMTP delivery for Ente verification emails";

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "SMTP host Museum uses to send verification emails.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 25;
        description = "SMTP port Museum uses to send verification emails.";
      };

      email = lib.mkOption {
        type = lib.types.str;
        description = "From email address used by Museum.";
      };

      senderName = lib.mkOption {
        type = lib.types.str;
        default = "Ente Photos";
        description = "Display name used for Ente verification emails.";
      };

      encryption = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum [ "tls" "ssl" ]);
        default = null;
        description = "Optional SMTP encryption mode. Leave null for local plaintext SMTP.";
      };
    };

    storage = {
      bucket = lib.mkOption {
        type = lib.types.str;
        description = "S3-compatible bucket used by Ente for photo object storage.";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        description = "S3-compatible endpoint URL.";
      };

      region = lib.mkOption {
        type = lib.types.str;
        description = "S3-compatible region name.";
      };

      hotStorage = lib.mkOption {
        type = lib.types.enum [
          "b2-eu-cen"
          "wasabi-eu-central-2-v3"
          "scw-eu-fr-v3"
        ];
        default = "b2-eu-cen";
        description = ''
          Museum's primary hot-storage key. Upstream requires one of its
          historical S3 storage identifiers even when the backing provider is a
          generic S3-compatible service.
        '';
      };

      usePathStyleUrls = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether Museum should use path-style S3 URLs.";
      };
    };

    secrets = {
      encryptionKeyFile = lib.mkOption {
        type = lib.types.path;
        description = "File containing Museum key.encryption.";
      };

      hashKeyFile = lib.mkOption {
        type = lib.types.path;
        description = "File containing Museum key.hash.";
      };

      jwtSecretFile = lib.mkOption {
        type = lib.types.path;
        description = "File containing Museum jwt.secret.";
      };

      s3AccessKeyFile = lib.mkOption {
        type = lib.types.path;
        description = "File containing the S3 access key.";
      };

      s3SecretKeyFile = lib.mkOption {
        type = lib.types.path;
        description = "File containing the S3 secret key.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.ente = {
      api = {
        enable        = true;
        enableLocalDB = true;
        domain        = cfg.apiDomain;

        nginx.enable = true;

        settings = {
          key = {
            encryption._secret = cfg.secrets.encryptionKeyFile;
            hash._secret       = cfg.secrets.hashKeyFile;
          };

          jwt.secret._secret = cfg.secrets.jwtSecretFile;

          s3 = {
            hot_storage.primary = cfg.storage.hotStorage;
            derived-storage     = cfg.storage.hotStorage;
            are_local_buckets   = false;
            use_path_style_urls = cfg.storage.usePathStyleUrls;

            ${cfg.storage.hotStorage} = {
              key._secret    = cfg.secrets.s3AccessKeyFile;
              secret._secret = cfg.secrets.s3SecretKeyFile;
              endpoint       = cfg.storage.endpoint;
              region         = cfg.storage.region;
              bucket         = cfg.storage.bucket;
            };
          };

          internal.disable-registration = cfg.disableRegistration;

          smtp = lib.mkIf cfg.smtp.enable ({
            inherit (cfg.smtp) host port email;
            sender-name = cfg.smtp.senderName;
          } // lib.optionalAttrs (cfg.smtp.encryption != null) {
            encryption = cfg.smtp.encryption;
          });
        };
      };

      web = {
        enable = true;
        domains = {
          api = cfg.apiDomain;
          inherit (cfg.domains) accounts cast albums photos;
        };
      };
    };

    services.nginx.virtualHosts =
      (lib.genAttrs webHostNames (_: {
        enableACME = true;
        forceSSL   = true;
      })) // {
        ${cfg.apiDomain} = {
          enableACME = true;
          forceSSL   = true;
          extraConfig = lib.mkForce ''
            client_max_body_size ${cfg.maxUploadSize};
          '';
          locations."/".extraConfig = ''
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
          '';
        };
      };
  };
}
