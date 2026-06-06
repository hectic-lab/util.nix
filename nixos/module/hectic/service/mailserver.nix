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

    services.postfix.settings.main = {
      # NOTE(yukkop): avoid Gmail rejection due to missing IPv6 PTR records.
      inet_protocols = lib.mkDefault "ipv4";

      # NOTE(yukkop): nixos-mailserver enables DANE by default. Some large MXes
      # currently fail certificate verification under this policy, which leaves
      # otherwise valid transactional mail deferred in the queue. Keep STARTTLS
      # opportunistic for outbound delivery rather than blocking mail entirely.
      smtp_tls_security_level = lib.mkForce "may";
      smtp_dns_support_level  = lib.mkForce "enabled";
      smtp_tls_policy_maps    = lib.mkForce "";
    };

    security.acme.acceptTerms       = true;
    security.acme.defaults.email    = "security@" + cfg.domain;
  };
}
