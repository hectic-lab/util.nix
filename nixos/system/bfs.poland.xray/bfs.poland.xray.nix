{
  inputs,
  flake,
  self,
}: {
  lib,
  pkgs,
  modulesPath,
  config,
  ...
}: let
  matrixBackend = "https://128.140.75.58";
  matrixHost = "accord.tube";
  elementEntryDomain = "element.bfs.band";
  polandEntryDomain = "bfs.band";
  backendProxyConfig = ''
    proxy_ssl_server_name on;
    proxy_ssl_name ${matrixHost};
    proxy_set_header Host ${matrixHost};
  '';
in {
  imports = [
    self.nixosModules.xray-system
    self.nixosModules.matrix-cluster
  ];

  hectic.generic.xray-system = {
    enable          = true;
    defaultSopsFile = ../../../sus/bfs.xray.yaml;
  };

  hectic.generic.matrix-cluster = {
    enable        = true;
    role          = "primary";
    matrixDomain  = "accord.tube";
    signingKeyFile = config.sops.secrets."matrix/signing-key".path;
    secretsFile    = config.sops.secrets."matrix/secrets".path;
    turnSecretFile = config.sops.secrets."matrix/turn-secret".path;
    publicIp       = "91.198.166.181";
    objectStorage.s3 = {
      bucket          = "matrix-hectic-lab";
      regionName      = "hel1";
      endpointUrl     = "https://hel1.your-objectstorage.com";
      credentialsFile = config.sops.secrets."matrix/object-storage/credentials".path;
    };
    replication = {
      peerHost     = "128.140.75.58";
      passwordFile = config.sops.secrets."matrix/postgres-replication-password".path;
    };
    acme = {
      enable                  = false;
      porkbunApiKeyFile       = config.sops.secrets."matrix/porkbun-api-key".path;
      porkbunSecretApiKeyFile = config.sops.secrets."matrix/porkbun-secret-api-key".path;
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "security@bfs.band";
  };

  services.nginx = {
    enable = true;

    virtualHosts.${polandEntryDomain} = {
      enableACME = true;
      forceSSL = true;

      locations."/".return = "302 https://${elementEntryDomain}";

      locations."=/.well-known/matrix/client" = {
        extraConfig = ''
          default_type application/json;
          add_header Access-Control-Allow-Origin *;
          add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
          add_header Access-Control-Allow-Headers "X-Requested-With, Content-Type, Authorization";
        '';
        return = ''200 '{
          "m.homeserver": {
            "base_url": "https://${polandEntryDomain}"
          },
          "m.identity_server": {
            "base_url": "https://vector.im"
          },
          "org.matrix.msc3575.proxy": {
            "url": "https://${polandEntryDomain}"
          },
          "org.matrix.msc4143.rtc_foci": [
            {
              "type": "livekit",
              "livekit_service_url": "https://${polandEntryDomain}/livekit/jwt"
            }
          ]
        }' '';
      };

      locations."= /livekit/jwt" = {
        proxyPass = "${matrixBackend}/livekit/jwt";
        extraConfig = backendProxyConfig;
      };

      locations."^~ /livekit/jwt/" = {
        proxyPass = "${matrixBackend}/livekit/jwt/";
        extraConfig = backendProxyConfig;
      };

      locations."= /livekit/sfu" = {
        proxyPass = "${matrixBackend}/livekit/sfu";
        proxyWebsockets = true;
        extraConfig = backendProxyConfig + ''
          proxy_send_timeout 120;
          proxy_read_timeout 120;
          proxy_buffering off;
          proxy_set_header Accept-Encoding gzip;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
        '';
      };

      locations."^~ /livekit/sfu/" = {
        proxyPass = "${matrixBackend}/livekit/sfu/";
        proxyWebsockets = true;
        extraConfig = backendProxyConfig + ''
          proxy_send_timeout 120;
          proxy_read_timeout 120;
          proxy_buffering off;
          proxy_set_header Accept-Encoding gzip;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
        '';
      };

      locations."^~ /_matrix/" = {
        proxyPass = "${matrixBackend}/_matrix/";
        extraConfig = backendProxyConfig;
      };

      locations."^~ /_synapse/client/" = {
        proxyPass = "${matrixBackend}/_synapse/client/";
        extraConfig = backendProxyConfig;
      };
    };

    virtualHosts.${elementEntryDomain} = {
      enableACME = true;
      forceSSL = true;

      locations."= /config.${elementEntryDomain}.json".return = "302 /config.json";

      root = pkgs.element-web.override {
        conf = {
          default_server_config = {
            "m.homeserver".base_url = "https://${polandEntryDomain}";
            "m.homeserver".server_name = matrixHost;
            "m.identity_server".base_url = "https://vector.im";
          };

          room_directory.servers = [ matrixHost ];

          default_theme = "dark";
          show_labs_settings = true;
        };
      };
    };
  };

  sops.secrets."matrix/signing-key" = {
    key      = "matrix/signing-key";
    owner    = "matrix-synapse";
    mode     = "0400";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };
  sops.secrets."matrix/postgres-replication-password" = {
    key      = "matrix/postgres-replication-password";
    owner    = "postgres";
    mode     = "0400";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };
  sops.secrets."matrix/object-storage/credentials" = {
    key      = "matrix/object-storage/credentials";
    owner    = "matrix-synapse";
    mode     = "0400";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };
  sops.secrets."matrix/secrets" = {
    key      = "matrix/secrets";
    owner    = "matrix-synapse";
    mode     = "0400";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };
  sops.secrets."matrix/turn-secret" = {
    key      = "matrix/turn-secret";
    owner    = "turnserver";
    group    = "turnserver";
    mode     = "0400";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };
  sops.secrets."matrix/porkbun-api-key" = {
    key      = "matrix/porkbun-api-key";
    mode     = "0400";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };
  sops.secrets."matrix/porkbun-secret-api-key" = {
    key      = "matrix/porkbun-secret-api-key";
    mode     = "0400";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };
}
