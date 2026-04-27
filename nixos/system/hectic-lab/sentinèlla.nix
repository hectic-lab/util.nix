{
  inputs,
  flake,
  self,
  domain,
  sslOpts,
  ...
}: { ... }: {
  hectic.services."sentinèlla" = {
    probe.enable = true;
    watcher = {
      enable             = true;
      pollingIntervalSec = 60;
      # TG_TOKEN= and TG_CHAT_ID= are read from sus/sentinella-default.yaml
      # (auto-declared by the module as sops.secrets."sentinèlla/watcher/environment")
    };
  };

  services.nginx = {
    virtualHosts."probe.${domain}" = sslOpts // {
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:5988";
      };
    };
  };
}
