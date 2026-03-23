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
  cfg = config.hectic.services.xmpp;
in {
  options = {
    hectic.services.xmpp = {
      enable = lib.mkEnableOption "General-purpose XMPP server (Prosody) for messaging clients like Monocles Chat";
      domain = lib.mkOption {
        type        = lib.types.str;
        description = ''
          Primary XMPP domain. Users will have JIDs like user@domain.
        '';
      };
      admins = lib.mkOption {
        type        = lib.types.listOf lib.types.str;
        default     = [];
        example     = [ "admin@example.org" ];
        description = ''
          List of admin JIDs.
        '';
      };
      allowRegistration = lib.mkOption {
        type        = lib.types.bool;
        default     = false;
        description = ''
          Allow in-band account registration from clients.
          If false, create accounts with: prosodyctl register <user> <domain> <password>
        '';
      };
      uploadFileSizeLimit = lib.mkOption {
        type        = lib.types.int;
        default     = 10485760;
        description = ''
          Maximum file upload size in bytes (default 10 MiB).
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.prosody = {
      enable = true;
      admins = cfg.admins;
      allowRegistration = cfg.allowRegistration;

      ssl = {
        cert = "/var/lib/acme/${cfg.domain}/fullchain.pem";
        key  = "/var/lib/acme/${cfg.domain}/key.pem";
      };

      virtualHosts.${cfg.domain} = {
        enabled = true;
        domain  = cfg.domain;
        ssl = {
          cert = "/var/lib/acme/${cfg.domain}/fullchain.pem";
          key  = "/var/lib/acme/${cfg.domain}/key.pem";
        };
      };

      muc = [
        { domain = "conference.${cfg.domain}"; }
      ];

      httpFileShare = {
        domain     = "upload.${cfg.domain}";
        size_limit = cfg.uploadFileSizeLimit;
      };
    };

    # Grant prosody read access to ACME certs (group is "nginx" since
    # the nginx vhost requests the cert via enableACME)
    users.users.prosody.extraGroups = [ "nginx" ];

    # nginx vhost handles ACME HTTP-01 challenge for the XMPP domain.
    # The cert also covers conference.* and upload.* subdomains.
    services.nginx = {
      enable = true;
      virtualHosts.${cfg.domain} = {
        enableACME = true;
        forceSSL   = true;
        locations."/".return = "301 https://meet.${cfg.domain}";
      };
    };

    security.acme = {
      acceptTerms = true;
      defaults = {
        email           = "hectic.yukkop.it@gmail.com";
        enableDebugLogs = true;
      };
      # Add MUC + upload subdomains to the nginx-managed cert
      certs.${cfg.domain} = {
        extraDomainNames = [
          "conference.${cfg.domain}"
          "upload.${cfg.domain}"
        ];
        reloadServices = [ "prosody" ];
      };
    };

    networking.firewall = {
      allowedTCPPorts = [
        5222  # c2s (client-to-server)
        5269  # s2s (server-to-server federation)
        80    # ACME HTTP-01 challenge
        443   # HTTPS
      ];
    };
  };
}
