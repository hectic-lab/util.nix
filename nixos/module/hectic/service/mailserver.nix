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
  cfg = config.services.mailserver;
  transformLoginAccounts = domain: input:
    builtins.listToAttrs (map (key: {
      name  = key + "@" + domain;
      value = input.${key};
    }) (builtins.attrNames input));
in {
  options = {
    services.mailserver.enable = lib.mkEnableOption "Mail server";

    services.mailserver.domain = lib.mkOption {
      type        = lib.types.str;
      description = "The domain name of the mail server";
    };

    services.mailserver.loginAccounts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          hashedPassword = lib.mkOption {
            type    = lib.types.nullOr lib.types.str;
            default = null;
          };
          hashedPasswordFile = lib.mkOption {
            type        = lib.types.nullOr lib.types.str;
            default     = null;
            description = ''
              Full path to a file containing the hashed password suitable
              for use with `chpasswd -e`.
            '';
          };
        };
      });
      default     = {};
      description = "Login accounts for the mail server";
    };
  };

  config = lib.mkIf cfg.enable {
    mailserver = {
      enable   = true;
      fqdn     = "mail." + cfg.domain;
      domains  = [ cfg.domain ];

      loginAccounts = transformLoginAccounts cfg.domain cfg.loginAccounts;

      certificateScheme = "acme-nginx";
    };

    security.acme.acceptTerms       = true;
    security.acme.defaults.email    = "security@" + cfg.domain;
  };
}
