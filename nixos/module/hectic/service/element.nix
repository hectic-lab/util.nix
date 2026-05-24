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
  legacyCfg = config.hectic.services.matrix;
  clusterCfg = config.hectic.generic.matrix-cluster;
  clusterSynapseEnabled =
    clusterCfg.enable
    && (if clusterCfg.overrideEnableSynapse != null then clusterCfg.overrideEnableSynapse else clusterCfg.role == "primary");
  enabled = legacyCfg.enable || clusterSynapseEnabled;
  matrixDomain = if legacyCfg.enable then legacyCfg.matrixDomain else clusterCfg.matrixDomain;
in {
  config = lib.mkIf enabled {
    services.nginx.virtualHosts."element.${matrixDomain}" = {
      enableACME = true;
      forceSSL = true;

      locations."= /config.element.${matrixDomain}.json".return = "302 /config.json";

      root = pkgs.element-web.override {
        conf = {
          default_server_config = {
            "m.homeserver".base_url = "https://${matrixDomain}";
            "m.homeserver".server_name = matrixDomain;
            "m.identity_server".base_url = "https://vector.im";
          };

          room_directory.servers = [
            matrixDomain
          ];

          default_theme = "dark";
          show_labs_settings = true;
        };
      };
    };
  };
}
