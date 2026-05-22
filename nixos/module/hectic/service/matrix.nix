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
  matrixUsers = builtins.attrNames cfg.users;
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
  config = lib.mkIf cfg.enable {
    services.matrix-synapse = {
      enable = true;
      extraConfigFiles = [
        cfg.secretsFile
      ];
      settings = {
          server_name = cfg.matrixDomain;
         public_baseurl = "https://${cfg.matrixDomain}";
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
  };
}
