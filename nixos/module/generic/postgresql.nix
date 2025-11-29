{ 
  inputs,
  self,
  flake
}:
{ 
  pkgs,
  config,
  lib,
  ...
}: let
  system = pkgs.system;
  cfg = config.services.postgresql;
  extensionFlags = {
    pg_cron = false;
    pgjwt = false;
    pg_net = false;
    pg_smtp_client = false;
    http = false;
    plsh = false;
    hemar = false;
  };
in {
  options = {
    services.postgresql = {
      lazzyExtensions = lib.mkOption {
        type = lib.types.attrsOf lib.types.bool;
        default = extensionFlags;
      };
      environment = lib.mkOption {
        type    = lib.types.attrsOf lib.types.str;
        default = {};
      };
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.services.postgresql.environment = cfg.environment;
    services.postgresql = {
      settings.shared_preload_libraries =
        lib.concatStringsSep ", "
          (lib.attrNames (
  	    lib.filterAttrs (n: v: v && 
  	         n != "http" 
  	      && n != "plsh" 
  	      && n != "pgjwt" 
  	      && n != "pg_smtp_client"
  	  ) cfg.lazzyExtensions));

      extensions = let
        packages = {
          inherit (cfg.package.pkgs) pg_net pgjwt pg_cron http pg_smtp_client plsh;
        };
      in
        lib.attrValues (
          lib.filterAttrs (n: v: v != null)
          (lib.mapAttrs' (
              name: enabled:
                if enabled
                then lib.nameValuePair name (packages.${name} or (throw "Package ${name} not found in pkgs"))
                else null
            )
            cfg.lazzyExtensions)
        );
    };
  };
}
