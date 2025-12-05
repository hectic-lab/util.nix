{ lib, config, ... }: let
  cfg = config.currentServer.matrix;
  shared_secret = "secret";
in {
  config = {
    services.coturn = rec {
      enable = true;
      realm = cfg.matrixDomain;
      use-auth-secret = true;
      static-auth-secret = shared_secret;
      cert = "${config.security.acme.certs.${realm}.directory}/full.pem";
      pkey = "${config.security.acme.certs.${realm}.directory}/key.pem";
      listening-ips = ["188.137.254.58"];
      no-tcp-relay = true;
      relay-ips = ["188.137.254.58"];
      listening-port = 3478;
      tls-listening-port = 5349;
      no-cli = true;

      extraConfig = ''
        verbose
      '';
    };

    networking.firewall = {
      allowedUDPPorts = [ 3478 5349 ];
      allowedTCPPorts = [ 3478 5349 ];
      allowedUDPPortRanges = [
        { from = 49152; to = 65535; }
      ];
    };

    services.matrix-synapse.settings = {
      turn_uris = [
        "turn:${cfg.matrixDomain}:3478?transport=udp"
        "turn:${cfg.matrixDomain}:3478?transport=tcp"
      ];
      turn_shared_secret = shared_secret;
    };
  };
}
