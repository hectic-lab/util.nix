{
  domain,
  ...
}: {
  config,
  ...
}: {
  hectic.services.attic = {
    enable          = true;
    hostName        = "cache.${domain}";
    environmentFile = config.sops.secrets."atticd/environment".path;
    storage = {
      bucket   = "cache-hectic-lab";
      endpoint = "https://hel1.your-objectstorage.com";
      region   = "hel1";
    };
  };

  services.nginx.virtualHosts."cache.${domain}" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8080";
    };
  };
}
