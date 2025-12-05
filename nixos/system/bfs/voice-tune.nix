{ lib, config, ... }: let
  cfg = config.currentServer.matrixDomain;
in {
  options = {
    currentServer.matrixDomain = lib.mkOption {
      type = lib.types.str;
      description = ''
        domain
      '';
    };
  };
  config = {
    services.coturn = {
      enable = true;
      realm = cfg.matrixDomain;

      listening-port = 3478;
      tls-listening-port = 5349;
      no-cli = true;
    };

    networking.firewall.allowedUDPPorts = [ 3478 5349 ];
    networking.firewall.allowedTCPPorts = [ 3478 5349 ];

    services.matrix-synapse.settings = {
      turn_uris = [
        "turn:your.domain:3478?transport=udp"
        "turns:your.domain:5349?transport=tcp"
      ];
      turn_shared_secret = "secret";
    };
  };
}
