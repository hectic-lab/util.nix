{
  inputs,
  flake,
  self,
  domain,
  sslOpts,
  ...
}: let
  port = 5869;
in {
  hectic = {
    services."sentinèlla".probe = {
      enable = true;
      inherit port;
    };
  };

  services.nginx =  {
    virtualHosts."probe.${domain}" = sslOpts // {
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${builtins.toString port}";
      };
    };
  };
}
