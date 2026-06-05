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
  hasClusterCfg = config.hectic ? generic && config.hectic.generic ? matrix-cluster;
  clusterCfg = if hasClusterCfg then config.hectic.generic.matrix-cluster else null;
  clusterSynapseEnabled =
    if hasClusterCfg
    then clusterCfg.enable
      && (if clusterCfg.overrideEnableSynapse != null then clusterCfg.overrideEnableSynapse else clusterCfg.role == "primary")
    else false;
  enabled = legacyCfg.enable || clusterSynapseEnabled;
  matrixDomain = if legacyCfg.enable then legacyCfg.matrixDomain else if hasClusterCfg then clusterCfg.matrixDomain else "";
  jitsiPreferredDomain =
    if legacyCfg.enable && config.hectic.services.jitsi.enable
    then config.hectic.services.jitsi.hostName
    else if hasClusterCfg then clusterCfg.jitsi.preferredDomain else null;
in {
  config = lib.mkIf enabled {
    services.nginx.virtualHosts."element.${matrixDomain}" = {
      enableACME = true;
      forceSSL = true;

      locations."= /config.element.${matrixDomain}.json".return = "302 /config.json";

      root = pkgs.hectic.element-web.override {
        conf = {
          default_server_config = {
            "m.homeserver".base_url = "https://${matrixDomain}";
            "m.homeserver".server_name = matrixDomain;
            "m.identity_server".base_url = "https://vector.im";
          };

          room_directory.servers = [
            matrixDomain
          ];

          jitsi = lib.optionalAttrs (jitsiPreferredDomain != null) {
            preferred_domain = jitsiPreferredDomain;
          };

          default_theme = "dark";
          show_labs_settings = true;
        };
      };
    };
  };
}
