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
  system = pkgs.stdenv.hostPlatform.system;
  cfg    = config.hectic.services."sentinèlla";

  probePort = 5988;
  peersDns  = "peers.sentinella.hectic-lab.com";
in {
  options = {
    hectic.services."sentinèlla" = {
      probe = {
        enable = lib.mkEnableOption "sentinèlla probe — HTTP server exposing this node's health";
        urls = lib.mkOption {
          type    = with lib.types; listOf str;
          default = [];
          description = "URLs the probe health-checks on GET /status.";
        };
        volumes = lib.mkOption {
          type    = with lib.types; listOf str;
          default = [];
          description = "Mount points reported on GET /disk. Empty means all volumes.";
        };
        authFile = lib.mkOption {
          type    = with lib.types; nullOr path;
          default = null;
          example = "config.sops.secrets.\"sentinella-probe-auth\".path";
          description = "Path to a file with lines of the form user:pass for Basic Auth.";
        };
        environmentFile = lib.mkOption {
          type    = with lib.types; nullOr path;
          default = null;
          description = ''
            Optional environment file for secrets. Supported variables:
              PORT=
              URLS=
              VOLUMES=
              AUTH_FILE=
          '';
        };
      };

      watcher = {
        enable = lib.mkEnableOption "sentinèlla watcher — polls peers discovered via DNS and sends Telegram alerts";
        self = lib.mkOption {
          type    = with lib.types; nullOr str;
          default = null;
          example = "1.2.3.4";
          description = ''
            Override the auto-detected local IP. When null (default) the watcher
            uses hostname -I to find all local IPs and excludes them from the
            peer list automatically. Set this only if the node is behind NAT or
            has a floating IP that hostname -I does not report correctly.
          '';
        };
        peersScheme = lib.mkOption {
          type    = lib.types.str;
          default = "http";
          description = "URL scheme used when connecting to peers (http or https).";
        };
        pollingIntervalSec = lib.mkOption {
          type    = lib.types.int;
          default = 3;
          description = "Seconds between polling rounds.";
        };
        tgToken = lib.mkOption {
          type    = with lib.types; nullOr str;
          default = null;
          description = "Telegram bot token. Prefer environmentFile for secrets.";
        };
        tgChatId = lib.mkOption {
          type    = with lib.types; nullOr str;
          default = null;
          description = "Telegram chat ID. Prefer environmentFile for secrets.";
        };
        environmentFile = lib.mkOption {
          type    = with lib.types; nullOr path;
          default = config.sops.secrets."sentinèlla/watcher/environment".path;
          defaultText = lib.literalExpression
            "config.sops.secrets.\"sentinèlla/watcher/environment\".path";
          example = "config.sops.secrets.\"sentinella-watcher-env\".path";
          description = ''
            Environment file for secrets. Defaults to the auto-declared SOPS
            secret sentinèlla/watcher/environment (resolved from
            sus/sentinella-default.yaml in the flake). Override the sopsFile
            via sops.secrets."sentinèlla/watcher/environment".sopsFile if you
            need a host-specific file instead.

            Supported variables:
              TG_TOKEN=
              TG_CHAT_ID=
              PEERS_TOKEN=   # Basic Auth token sent to all peers
              SELF=
              PEERS_DNS=
          '';
        };
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.probe.enable {
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [
          probePort     
        ];
      };

      systemd.services."sentinella-probe" = {
        description = "sentinèlla probe — node health HTTP server";
        after       = [ "network.target" ];
        wantedBy    = [ "multi-user.target" ];
        serviceConfig = lib.mkMerge [
          {
            Type            = "simple";
            ExecStart       = "${self.packages.${system}."sentinèlla"}/bin/probe";
            Restart         = "always";
            RestartSec      = "5s";
            TimeoutStopSec  = "30s";
            KillSignal      = "SIGTERM";
            KillMode        = "mixed";
            RemainAfterExit = false;
            StandardOutput  = "journal";
            StandardError   = "journal";
            Environment = lib.filter (s: s != "") [
              "PORT=${builtins.toString probePort}"
              (lib.optionalString (cfg.probe.urls    != []) "URLS=${lib.concatStringsSep " " cfg.probe.urls}")
              (lib.optionalString (cfg.probe.volumes != []) "VOLUMES=${lib.concatStringsSep " " cfg.probe.volumes}")
              (lib.optionalString (cfg.probe.authFile != null) "AUTH_FILE=${cfg.probe.authFile}")
            ];
          }
          (lib.mkIf (cfg.probe.environmentFile != null) {
            EnvironmentFile = cfg.probe.environmentFile;
          })
        ];
      };
    })

    (lib.mkIf cfg.watcher.enable {
      sops.secrets."sentinèlla/watcher/environment" = lib.mkDefault {
        sopsFile = "${flake}/sus/sentinella-default.yaml";
      };

      systemd.services."sentinella-watcher" = {
        description = "sentinèlla watcher — p2p peer monitor";
        after       = [ "network.target" ];
        wantedBy    = [ "multi-user.target" ];
        serviceConfig = lib.mkMerge [
          {
            Type            = "simple";
            ExecStart       = "${self.packages.${system}."sentinèlla"}/bin/watcher";
            Restart         = "always";
            RestartSec      = "5s";
            TimeoutStopSec  = "30s";
            KillSignal      = "SIGTERM";
            KillMode        = "mixed";
            RemainAfterExit = false;
            StandardOutput  = "journal";
            StandardError   = "journal";
            StateDirectory  = "sentinella";
            Environment = lib.filter (s: s != "") [
              "PEERS_DNS=${peersDns}"
              (lib.optionalString (cfg.watcher.self != null) "SELF=${cfg.watcher.self}")
              "PEERS_PORT=${builtins.toString probePort}"
              "PEERS_SCHEME=${cfg.watcher.peersScheme}"
              "POLLING_INTERVAL_SEC=${builtins.toString cfg.watcher.pollingIntervalSec}"
              "STATE_DIR=/var/lib/sentinella"
              (lib.optionalString (cfg.watcher.tgToken  != null) "TG_TOKEN=${cfg.watcher.tgToken}")
              (lib.optionalString (cfg.watcher.tgChatId != null) "TG_CHAT_ID=${cfg.watcher.tgChatId}")
            ];
          }
          (lib.mkIf (cfg.watcher.environmentFile != null) {
            EnvironmentFile = cfg.watcher.environmentFile;
          })
        ];
      };
    })
  ];
}
