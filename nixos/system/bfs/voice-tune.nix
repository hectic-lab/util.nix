{ lib, config, ... }: let
  cfg = config.currentServer.matrix;
in {
  config = {
    services.coturn = {
      enable = true;
      realm = cfg.matrixDomain;

      listening-port = 3478;
      tls-listening-port = 5349;
      no-cli = true;
    };

    networking.firewall = {
      allowedUDPPorts = [ 3478 5349 ];
      allowedTCPPorts = [ 3478 5349 ];
      allowedUDPPortRanges = [
        { from = 49152; to = 65535; }
      ];
      allowedTCPPortRanges = [
        { from = 50000; to = 51000; }
      ];
    };

    services.matrix-synapse.settings = {
      turn_uris = [
        "turn:${cfg.matrixDomain}:3478?transport=udp"
        "turns:${cfg.matrixDomain}:5349?transport=tcp"
      ];
      turn_shared_secret = "secret";
    };
  };
}
