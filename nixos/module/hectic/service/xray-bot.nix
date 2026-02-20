{ inputs, flake, self }:
{ config, pkgs, lib, ... }: let
  cfg = config.hectic.services.xray-bot;
  system = pkgs.system;

  serverSubmodule = {
    options = {
      address = lib.mkOption {
        type = lib.types.str;
        description = "Public IP or domain of this server.";
        example = "188.137.254.58";
      };
      publicKey = lib.mkOption {
        type = lib.types.str;
        description = ''
          Reality public key (client-side).
          Required for reality security. Derived from the server's private key.
        '';
      };
    };
  };
in {
  options = {
    hectic.services.xray-bot = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            xrayConfigPath = lib.mkOption {
              type = lib.types.path;
              description = ''
                Path to the Xray server config JSON file.
                The bot reads this to extract client UUIDs and
                shared stream settings (security, network, sni, etc.).
                All servers are mirrors sharing the same config.
              '';
            };
            servers = lib.mkOption {
              type = lib.types.attrsOf (lib.types.submodule serverSubmodule);
              description = ''
                Server endpoints. Attribute name is the short display name
                shown to users (e.g. "NL", "DE").
                Security settings (sni, shortIds, flow, etc.) are read
                from the shared Xray config automatically.
              '';
              example = lib.literalExpression /* nix */ ''
                {
                  "NL" = {
                    address   = "1.2.3.4";
                    publicKey = "abc123...";
                  };
                  "DE" = {
                    address   = "5.6.7.8";
                    publicKey = "def456...";
                  };
                }
              '';
            };
            environmentPath = lib.mkOption {
              type = lib.types.path;
              description = ''
                Path to environment file with secrets:
                  BOT_TOKEN=<telegram bot token>
              '';
            };
            databaseUrl = lib.mkOption {
              type = lib.types.str;
              default = "postgresql:///xray_bot";
              description = "PostgreSQL connection URL.";
            };
            postgresqlPackage = lib.mkOption {
              type = lib.types.package;
              default = pkgs.postgresql_17;
              description = "PostgreSQL package to use.";
            };
            migrationDir = lib.mkOption {
              type = lib.types.path;
              default = "${self.packages.${system}.xray-bot.src}/migration";
              description = "Path to migration directory.";
            };
          };
        }
      );
      default = { };
      description = "Declarative xray-bot instances.";
    };
  };
  config = let
    instances    = lib.mapAttrs (name: val: val // { inherit name; }) cfg;
    instancesArr = builtins.attrValues instances;

    # Convert servers attrset to JSON: only name, address, public_key.
    # Stream settings (port, security, sni, etc.) come from the Xray config.
    serversToJson = servers: builtins.toJSON (
      lib.mapAttrsToList (name: srv: {
        inherit name;
        inherit (srv) address;
        public_key = srv.publicKey;
      }) servers
    );
  in lib.mkIf (instancesArr != []) {
    services.postgresql = lib.mkMerge (map (inst: {
      enable = true;
      package = inst.postgresqlPackage;
      ensureDatabases = [ "xray_bot_${inst.name}" ];
      ensureUsers = [{
        name = "xray-bot-${inst.name}";
        ensureDBOwnership = true;
      }];
    }) instancesArr);

    systemd.services = lib.mkMerge (map (inst: let
      dbUrl = if inst.databaseUrl == "postgresql:///xray_bot"
              then "postgresql:///xray_bot_${inst.name}?host=/run/postgresql"
              else inst.databaseUrl;
    in {
      "xray-bot-${inst.name}-migrate" = {
        description = "xray-bot ${inst.name} database migration";
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "xray-bot-${inst.name}";
          ExecStart = lib.concatStringsSep " " [
            "${self.packages.${system}.migrator}/bin/migrator"
            "--db-url" dbUrl
            "--migration-dir" (toString inst.migrationDir)
            "migrate" "up" "all"
          ];
          RemainAfterExit = true;
        };
      };
      "xray-bot-${inst.name}" = {
        description = "xray-bot ${inst.name}";
        after = [ "network.target" "postgresql.service" "xray-bot-${inst.name}-migrate.service" ];
        requires = [ "xray-bot-${inst.name}-migrate.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          User = "xray-bot-${inst.name}";
          ExecStart = "${self.packages.${system}.xray-bot}/bin/xray-bot";
          Restart = "always";
          RestartSec = "5s";
          EnvironmentFile = inst.environmentPath;
          Environment = [
            "DATABASE_URL=${dbUrl}"
            "XRAY_CONFIG_PATH=${toString inst.xrayConfigPath}"
            "XRAY_SERVERS=${serversToJson inst.servers}"
          ];
          TimeoutStopSec = "30s";
          KillSignal = "SIGTERM";
          KillMode = "mixed";
          StandardOutput = "journal";
          StandardError = "journal";
        };
      };
    }) instancesArr);

    users.users = lib.mkMerge (map (inst: {
      "xray-bot-${inst.name}" = {
        isSystemUser = true;
        group = "xray-bot-${inst.name}";
      };
    }) instancesArr);

    users.groups = lib.mkMerge (map (inst: {
      "xray-bot-${inst.name}" = { };
    }) instancesArr);
  };
}
