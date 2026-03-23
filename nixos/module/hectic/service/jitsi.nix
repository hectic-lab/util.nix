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
  cfg = config.hectic.services.jitsi;
in {
  options = {
    hectic.services.jitsi = {
      enable = lib.mkEnableOption "Jitsi Meet video conferencing with Prosody XMPP backend";
      hostName = lib.mkOption {
        type        = lib.types.str;
        description = ''
          FQDN for the Jitsi Meet instance (e.g. "meet.example.org").
          Prosody VirtualHosts, nginx, and ACME certs are derived from this.
        '';
      };
      secureDomain = lib.mkOption {
        type        = lib.types.bool;
        default     = false;
        description = ''
          Require authentication to create rooms. Guests can still join
          existing rooms anonymously.
        '';
      };
      lockdown = lib.mkOption {
        type        = lib.types.bool;
        default     = false;
        description = ''
          Restrict Prosody to localhost only (no S2S federation, c2s
          only on 127.0.0.1). Set to false when running alongside a
          general-purpose XMPP server (hectic.services.xmpp).
        '';
      };
      videobridgePasswordFile = lib.mkOption {
        type        = lib.types.nullOr lib.types.path;
        default     = null;
        description = ''
          Path to a file containing the Jitsi Videobridge XMPP password.
          If null, a random password is auto-generated.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.jitsi-meet = {
      enable   = true;
      hostName = cfg.hostName;

      prosody = {
        enable   = true;
        lockdown = cfg.lockdown;
      };

      nginx.enable = true;
      videobridge = {
        enable = true;
      } // lib.optionalAttrs (cfg.videobridgePasswordFile != null) {
        passwordFile = cfg.videobridgePasswordFile;
      };
      jicofo.enable = true;

      secureDomain = lib.mkIf cfg.secureDomain {
        enable = true;
      };
    };

    services.jitsi-videobridge.openFirewall = true;

    services.nginx.virtualHosts.${cfg.hostName} = {
      enableACME = true;
      forceSSL   = true;
    };

    security.acme = {
      acceptTerms = true;
      defaults = {
        email          = "hectic.yukkop.it@gmail.com";
        enableDebugLogs = true;
      };
    };

    networking.firewall = {
      allowedTCPPorts = [
        80 443   # HTTP/HTTPS (nginx + ACME)
        5222     # XMPP c2s (if not locked down)
      ];
    };
  };
}
