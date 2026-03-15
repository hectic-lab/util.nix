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
in {
  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."element.${cfg.matrixDomain}" = {
      enableACME = true;
      forceSSL = true;

      root = pkgs.element-web.override {
        conf = {
          default_server_config = {
            "m.homeserver".base_url = "https://${cfg.matrixDomain}";
            "m.identity_server".base_url = "https://vector.im";
          };

          default_theme = "dark";
          show_labs_settings = true;
        };
      };
    };
  };
}
