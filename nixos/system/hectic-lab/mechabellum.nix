{
  inputs,
  domain,
  sslOpts,
  ...
}: {
  pkgs,
  ...
}: let
  mechDomain = "mechabellum.${domain}";
  apiHost = "127.0.0.1";
  apiPort = 8010;
  system = pkgs.stdenv.hostPlatform.system;
in {
  imports = [
    inputs.mechabellum-replay-analysis.nixosModules.default
  ];

  mechabellum.api = {
    enable = true;
    host = apiHost;
    port = apiPort;
    extraEnvironment = {
      CORS_ALLOWED_ORIGINS = "https://${mechDomain}";
    };
  };

  mechabellum.worker = {
    enable = true;
  };

  services.nginx.virtualHosts."${mechDomain}" = {
    enableACME = true;
    forceSSL = true;
    root = inputs.mechabellum-replay-analysis.packages.${system}.frontend;

    locations."/api" = {
      proxyPass = "http://${apiHost}:${builtins.toString apiPort}";
      extraConfig = ''
        proxy_http_version 1.1;
      '';
    };

    locations."/" = {
      tryFiles = "$uri $uri/ /index.html";
    };
  };
}
