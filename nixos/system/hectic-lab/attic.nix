{
  domain,
  ...
}: { ... }: {
  hectic.services.attic = {
    enable   = true;
    hostName = "cache.${domain}";
  };

  services.nginx.virtualHosts."cache.${domain}" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8080";
    };
  };
}
