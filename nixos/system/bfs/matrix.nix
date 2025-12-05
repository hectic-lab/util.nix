{ pkgs, lib, config, ... }: let
  cfg = config.currentServer.matrix;
in {
  options = {
      currentServer.matrix = {
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

      };
  };
  config  = {
    services.matrix-synapse = {
      enable = true;
      settings = {
        server_name = cfg.matrixDomain;
        public_baseurl = "https://${cfg.matrixDomain}";
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
                ];
                compress = false; 
              }
            ];
          } 
        ];

        enable_registration = true;
        enable_registration_without_verification = true;

        registration_shared_secret = "secret1";
        macaroon_secret_key        = "secret2";
        form_secret                = "secret3";
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
      port = cfg.postgresql.port;
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
  };
}
