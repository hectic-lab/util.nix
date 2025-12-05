{ pkgs, lib, config, ... }: let
  cfg = config.currentServer.matrix;
in {
  config  = let 
    keyFile = "/run/livekit.key";
  in {
    services.livekit = {
      enable = true;
      openFirewall = true;
      settings.room.auto_create = false;
      inherit keyFile;
    };

    services.lk-jwt-service = {
      enable = true;
      livekitUrl = "wss://${cfg.matrixDomain}/livekit/sfu";
      inherit keyFile;
    };

    systemd.services.livekit-key = {
      before = [ "lk-jwt-service.service" "livekit.service" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ livekit coreutils gawk ];
      script = ''
        echo "Key missing, generating key"
        echo "lk-jwt-service: $(livekit-server generate-keys | tail -1 | awk '{print $3}')" > "${keyFile}"
      '';
      serviceConfig.Type = "oneshot";
      unitConfig.ConditionPathExists = "!${keyFile}";
    };

    systemd.services.lk-jwt-service.environment.LIVEKIT_FULL_ACCESS_HOMESERVERS =
      cfg.matrixDomain;

    services.nginx = {
      enable = true;
      virtualHosts.${cfg.matrixDomain} = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8008";
        };

        locations."=/.well-known/matrix/client" = {
          extraConfig = ''
            default_type application/json;
            add_header Access-Control-Allow-Origin *;
          '';
          return = "200 '{\
            \"m.homeserver\": {\
              \"base_url\": \"https://${cfg.matrixDomain}\"\
            },\
            \"m.identity_server\": {\
              \"base_url\": \"https://vector.im\"\
            },\
            \"org.matrix.msc3575.proxy\": {\
              \"url\": \"https://${cfg.matrixDomain}\"\
            },\
            \"org.matrix.msc4143.rtc_foci\": [\
              {\
                \"type\": \"livekit\",\
                \"livekit_service_url\": \"https://${cfg.matrixDomain}/livekit/jwt\"\
              }\
            ]\
          }'";
        };

        locations."^~ /livekit/jwt/" = {
          priority = 400;
          proxyPass = "http://[::1]:${toString config.services.lk-jwt-service.port}/";
        };

        locations."^~ /livekit/sfu/" = {
          priority = 400;
          proxyPass = "http://[::1]:${toString config.services.livekit.settings.port}/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_send_timeout 120;
            proxy_read_timeout 120;
            proxy_buffering off;
            proxy_set_header Accept-Encoding gzip;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
          '';
        };
      };
    };

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [
        8448
      ];
    };
  };
}
