{
  inputs,
  flake,
  self,
}:
{
  lib,
  config,
  ...
}: let
  cfg = config.hectic.services.matrix;
in {
  options = {
    hectic.services.matrix = {
      turnSecretFile = lib.mkOption {
        type = lib.types.path;
        description = ''
          path to env file with matrix secrets

          just raw secret
        '';
      };
      publicIp = lib.mkOption {
        type = lib.types.str;
        description = ''
          public IP address of the server, used by coturn for
          listening and relay
        '';
      };
    };
  };
  config = lib.mkIf cfg.enable {
    services.coturn = rec {
      enable = true;
      realm = cfg.matrixDomain;
      use-auth-secret = true;
      static-auth-secret-file = cfg.turnSecretFile;
      cert = "${config.security.acme.certs.${realm}.directory}/full.pem";
      pkey = "${config.security.acme.certs.${realm}.directory}/key.pem";
      listening-ips = [cfg.publicIp];
      no-tcp-relay = true;
      relay-ips = [cfg.publicIp];
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
    };
  };
}
