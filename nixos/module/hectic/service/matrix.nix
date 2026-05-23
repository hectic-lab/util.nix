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
  cfg = config.hectic.services.matrix;
  s3Cfg = cfg.objectStorage.s3;

  matrixUsers = builtins.attrNames cfg.users;

  s3Plugin = pkgs.matrix-synapse-plugins.matrix-synapse-s3-storage-provider;
  s3ConfigDir = "/run/matrix-synapse";
  s3ConfigFile = "${s3ConfigDir}/s3-media-storage.yaml";

  mkUserRegistration = name: let
    user = cfg.users.${name};
    adminFlag = if user.admin then "--admin" else "--no-admin";
  in ''
    if [ ! -r "${user.passwordFile}" ]; then
      printf 'Missing Matrix password file for %s: %s\n' '${name}' '${user.passwordFile}' >&2
      exit 1
    fi

    ${pkgs.matrix-synapse}/bin/register_new_matrix_user \
      -u '${name}' \
      -p "$(tr -d '\n' < "${user.passwordFile}")" \
      -k "$REGISTRATION_SHARED_SECRET" \
      ${adminFlag} \
      http://127.0.0.1:8008 || true
  '';

  mkS3Config = ''
    if [ ! -r "${s3Cfg.credentialsFile}" ]; then
      printf 'Missing Matrix object storage credentials file: %s\n' '${s3Cfg.credentialsFile}' >&2
      exit 1
    fi

    . "${s3Cfg.credentialsFile}"

    if [ -z "$ACCESS_KEY_ID" ] || [ -z "$SECRET_ACCESS_KEY" ]; then
      printf 'ACCESS_KEY_ID or SECRET_ACCESS_KEY missing in %s\n' '${s3Cfg.credentialsFile}' >&2
      exit 1
    fi

    mkdir -p "${s3ConfigDir}"

    cat > "${s3ConfigFile}" <<EOF
    media_storage_providers:
      - module: s3_storage_provider.S3StorageProviderBackend
        store_local: ${lib.boolToString s3Cfg.storeLocal}
        store_remote: ${lib.boolToString s3Cfg.storeRemote}
        store_synchronous: ${lib.boolToString s3Cfg.storeSynchronous}
        config:
          bucket: ${s3Cfg.bucket}
          endpoint_url: ${s3Cfg.endpointUrl}
          region_name: ${s3Cfg.regionName}
          prefix: "${s3Cfg.prefix}"
          storage_class: "${s3Cfg.storageClass}"
          threadpool_size: ${toString s3Cfg.threadpoolSize}
          access_key_id: $ACCESS_KEY_ID
          secret_access_key: $SECRET_ACCESS_KEY
    EOF

    chown matrix-synapse:matrix-synapse "${s3ConfigFile}"
    chmod 0400 "${s3ConfigFile}"
  '';

  mkS3SyncScript = ''
    ${s3Plugin}/bin/s3_media_upload write
    ${s3Plugin}/bin/s3_media_upload upload "${s3Cfg.mediaStorePath}" "${s3Cfg.bucket}" \
      --endpoint-url "${s3Cfg.endpointUrl}" \
      --storage-class "${s3Cfg.storageClass}" \
      --prefix "${s3Cfg.prefix}" \
      ${lib.optionalString s3Cfg.sync.deleteLocalAfterUpload "--delete"}
    cat > /tmp/synapse-merge-config.py << 'PYEOF'
import yaml
with open("${config.services.matrix-synapse.configFile}") as f:
    config = yaml.safe_load(f)
with open("${cfg.secretsFile}") as f:
    secrets = yaml.safe_load(f)
config.update(secrets)
config.setdefault("database", {}).setdefault("args", {})
config["database"]["args"].setdefault("password", "")
config["database"]["args"].setdefault("host", "/run/postgresql")
config["database"]["args"].setdefault("port", 5432)
with open("/tmp/synapse-combined-config.yaml", "w") as f:
    yaml.dump(config, f, default_flow_style=False)
PYEOF
    ${pkgs.python3.withPackages (ps: [ps.pyyaml])}/bin/python3 /tmp/synapse-merge-config.py
    ${s3Plugin}/bin/s3_media_upload update-db --homeserver-config-path /tmp/synapse-combined-config.yaml 0s
    rm -f /tmp/synapse-combined-config.yaml
    ${s3Plugin}/bin/s3_media_upload check-deleted "${s3Cfg.mediaStorePath}"
  '';
in {
  options = {
    hectic.services.matrix = {
      enable = lib.mkEnableOption "Matrix Synapse homeserver with PostgreSQL and nginx";

      secretsFile = lib.mkOption {
        type = lib.types.path;
        description = ''
          path to env file with matrix secrets

          content:
          registration_shared_secret:
          macroon_secret_key
          form_secret
        '';
      };

      postgresql = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 5432;
          description = ''
            postgres port
          '';
        };

        initialEnvFile = lib.mkOption {
          type = lib.types.path;
          description = ''
            path to env file with postgresql initial secrets

            content:
            POSTGRESQL_PASSWORD=
          '';
        };
      };

      matrixDomain = lib.mkOption {
        type = lib.types.str;
        description = ''
          domain to matrix
        '';
      };

      maxUploadSize = lib.mkOption {
        type = lib.types.str;
        default = "100M";
        description = ''
          Maximum file upload size accepted by Synapse and nginx.
        '';
      };

      objectStorage.s3 = {
        enable = lib.mkEnableOption "S3-compatible object storage for Matrix media";

        bucket = lib.mkOption {
          type = lib.types.str;
          description = ''
            Bucket name used for Matrix media objects.
          '';
        };

        regionName = lib.mkOption {
          type = lib.types.str;
          description = ''
            Region name passed to the Synapse S3 storage provider.
          '';
        };

        endpointUrl = lib.mkOption {
          type = lib.types.str;
          description = ''
            S3-compatible endpoint URL.
          '';
        };

        credentialsFile = lib.mkOption {
          type = lib.types.path;
          description = ''
            Path to an env-style file containing:
              ACCESS_KEY_ID=
              SECRET_ACCESS_KEY=
          '';
        };

        mediaStorePath = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/matrix-synapse/media_store";
          description = ''
            Local Synapse media store path used before upload to object storage.
          '';
        };

        prefix = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            Optional object key prefix inside the bucket.
          '';
        };

        storageClass = lib.mkOption {
          type = lib.types.str;
          default = "STANDARD";
          description = ''
            Storage class passed to the upload tool.
          '';
        };

        threadpoolSize = lib.mkOption {
          type = lib.types.int;
          default = 40;
          description = ''
            Worker pool size for the Synapse S3 storage provider.
          '';
        };

        storeLocal = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Mirror local uploads to object storage.
          '';
        };

        storeRemote = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Mirror remotely-fetched media to object storage.
          '';
        };

        storeSynchronous = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Wait for object storage upload before completing the client request.
          '';
        };

        sync = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Periodically migrate older local media to object storage.
            '';
          };

          olderThan = lib.mkOption {
            type = lib.types.str;
            default = "1d";
            description = ''
              Age threshold passed to `s3_media_upload update`.
            '';
          };

          onCalendar = lib.mkOption {
            type = lib.types.str;
            default = "hourly";
            description = ''
              systemd timer schedule for media sync.
            '';
          };

          deleteLocalAfterUpload = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Remove local media after successful object storage upload.
            '';
          };
        };
      };

      users = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            passwordFile = lib.mkOption {
              type = lib.types.str;
              description = ''
                Full path to a file containing the Matrix user's password.
              '';
            };

            admin = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Whether to create the Matrix user as an admin.
              '';
            };
          };
        });
        default = {};
        description = ''
          Declarative Matrix users to provision after Synapse starts.
        '';
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      services.matrix-synapse = {
        enable = true;
        plugins = lib.optional s3Cfg.enable s3Plugin;
        extraConfigFiles = [
          cfg.secretsFile
        ] ++ lib.optional s3Cfg.enable s3ConfigFile;

        settings = {
          server_name = cfg.matrixDomain;
          public_baseurl = "https://${cfg.matrixDomain}";
          max_upload_size = cfg.maxUploadSize;
          media_store_path = lib.mkIf s3Cfg.enable s3Cfg.mediaStorePath;

          experimental_features = {
            msc3266_enabled = true;
            msc4140_enabled = true;
            msc4143_enabled = true;
            msc4222_enabled = true;
          };

          matrix_rtc = {
            transports = [
              {
                type = "livekit";
                livekit_service_url = "https://${cfg.matrixDomain}/livekit/jwt";
              }
            ];
          };

          listeners = [
            {
              port = 8008;
              bind_addresses = [ "0.0.0.0" ];
              type = "http";
              tls = false;
              resources = [
                {
                  names = [
                    "client"
                    # Ability speak between different matrix servers and get
                    # global id, requires .well-known
                    "federation"
                    "openid"
                  ];
                  compress = false;
                }
              ];
            }
          ];

          enable_registration = true;
          enable_registration_without_verification = true;
        };
      };

      environment.systemPackages = [
        pkgs.matrix-synapse
      ];

      services.postgresql = {
        enable = true;
        package = pkgs.postgresql_17;

        initdbArgs = [
          "--locale=C"
          "--encoding=UTF8"
        ];

        enableTCPIP = true;
        settings.port = cfg.postgresql.port;
        authentication = builtins.concatStringsSep "\n" [
          "local all         all           trust"
          "host  sameuser    all           127.0.0.1/32 scram-sha-256"
          "host  sameuser    all           ::1/128 scram-sha-256"
          "host  all         all           ::1/128 scram-sha-256"
          "host  all         all           0.0.0.0/0 scram-sha-256"

          "host  replication postgres      127.0.0.1/32   scram-sha-256"
          "host  replication postgres      ::1/128        scram-sha-256"
        ];

        settings = {
          wal_level = "replica";
          max_wal_senders = 10;
        };

        ensureUsers = [
          {
            name = "matrix-synapse";
            ensureClauses.login = true;
            ensureDBOwnership = true;
          }
        ];

        ensureDatabases = [
          "matrix-synapse"
        ];

        initialScript = pkgs.writeText "init-sql-script" ''
          -- setup password from env/sops
          DO $$#!${pkgs.dash}/bin/dash
            set -e
            . ${cfg.postgresql.initialEnvFile}
            psql -Atc "ALTER USER postgres WITH PASSWORD '$POSTGRESQL_PASSWORD'";
          $$ LANGUAGE plsh;

          CREATE ROLE myuser LOGIN PASSWORD 'matrix-synapse';
        '';
      };

      services.nginx = {
        enable = true;
        virtualHosts.${cfg.matrixDomain} = {
          forceSSL = true;
          enableACME = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:8008";
            extraConfig = ''
              client_max_body_size ${cfg.maxUploadSize};
            '';
          };
          locations."=/.well-known/matrix/server" = {
            extraConfig = ''
              default_type application/json;
              add_header Access-Control-Allow-Origin *;
              add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
              add_header Access-Control-Allow-Headers "X-Requested-With, Content-Type, Authorization";
            '';
            return = "200 '{\"m.server\": \"${cfg.matrixDomain}:443\"}'";
          };
        };
      };

      security.acme = {
        acceptTerms = true;
        defaults = {
          email = "hectic.yukkop.it@gmail.com";
          enableDebugLogs = true;
        };
      };

      systemd.services.matrix-synapse-users = lib.mkIf (matrixUsers != []) {
        description = "Provision Matrix Synapse users";
        wantedBy = [ "multi-user.target" ];
        after = [ config.services.matrix-synapse.serviceUnit ];
        requires = [ config.services.matrix-synapse.serviceUnit ];
        path = with pkgs; [ curl coreutils gawk ];
        serviceConfig = {
          Type = "oneshot";
          User = "matrix-synapse";
        };
        script = ''
          until curl -sf http://127.0.0.1:8008/_matrix/client/versions >/dev/null; do
            sleep 2
          done

          REGISTRATION_SHARED_SECRET="$(awk -F': *' '$1 == "registration_shared_secret" { print $2; exit }' "${cfg.secretsFile}")"

          if [ -z "$REGISTRATION_SHARED_SECRET" ]; then
            printf 'registration_shared_secret not found in %s\n' '${cfg.secretsFile}' >&2
            exit 1
          fi

${builtins.concatStringsSep "\n" (map mkUserRegistration matrixUsers)}
        '';
      };
    })

    (lib.mkIf (cfg.enable && s3Cfg.enable) {
      systemd.services.matrix-synapse-s3-config = {
        description = "Generate Synapse S3 media storage config";
        before = [ config.services.matrix-synapse.serviceUnit ];
        requiredBy = [ config.services.matrix-synapse.serviceUnit ];
        serviceConfig.Type = "oneshot";
        script = mkS3Config;
      };

      systemd.services.matrix-synapse-s3-media-sync = lib.mkIf s3Cfg.sync.enable {
        description = "Sync Matrix media to S3-compatible object storage";
        after = [ config.services.matrix-synapse.serviceUnit ];
        wants = [ config.services.matrix-synapse.serviceUnit ];
        serviceConfig = {
          Type = "oneshot";
          User = "matrix-synapse";
          WorkingDirectory = "/var/lib/matrix-synapse";
        };
        script = mkS3SyncScript;
      };

      systemd.timers.matrix-synapse-s3-media-sync = lib.mkIf s3Cfg.sync.enable {
        wantedBy = [ "timers.target" ];
        timerConfig.OnCalendar = s3Cfg.sync.onCalendar;
      };
    })
  ];
}
