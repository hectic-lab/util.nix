{
  inputs,
  flake,
  self,
  domain,
  sslOpts,
  ...
}: { config, ... }: let
  port = 5869;
in {
  hectic.services."sentinèlla" = {
    probe = {
      enable = true;
      inherit port;
    };
    watcher = {
      enable              = true;
      peersDns            = "peers.${domain}";
      peersPort           = port;
      pollingIntervalSec  = 60;
      # TG_TOKEN= and TG_CHAT_ID= are set via this environment file
      # Add the following to sus/hectic-lab.yaml under sentinèlla/watcher/:
      #   environment: |
      #     TG_TOKEN=<bot-token>
      #     TG_CHAT_ID=<chat-id>
      environmentFile = config.sops.secrets."sentinèlla/watcher/environment".path;
    };
  };

  sops.secrets."sentinèlla/watcher/environment" = {};

  services.nginx = {
    virtualHosts."probe.${domain}" = sslOpts // {
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${builtins.toString port}";
      };
    };
  };
}
