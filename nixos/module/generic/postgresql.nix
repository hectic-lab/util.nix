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
      script = lib.mkOption {
        type = with lib; types.nullOr types.path;
        default = null;
        example = lib.literalExpression ''
          pkgs.writeText "init-sql-script" '''
            alter user postgres with password 'myPassword';
          ''';'';

        description = ''
          A file containing SQL statements to execute on stratup or any time you change it.
        '';
      };
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.services.postgresql-script= lib.mkIf (cfg.script != null) {
      description = "Some postgresql settings";
      after = [ "postgresql.service" ];
      wants = [ "postgresql.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.dash}/bin/dash ${pkgs.writeText "sql-script" ''
          #!/${pkgs.dash}/bin/dash 

          set -e

          alias psql='${cfg.package}/bin/psql -v ON_ERROR_STOP=1 -p "${builtins.toString cfg.port}" -U postgres -d postgres'

          ${builtins.readFile cfg.script}
        ''}";
      };
      path = [ ];
      wantedBy = [ "multi-user.target" ];
    };
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
