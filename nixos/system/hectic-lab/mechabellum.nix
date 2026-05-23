{
  inputs,
  flake,
  self,
  domain,
  sslOpts,
  ...
}: {
  pkgs,
  lib,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;

  mechDomain = "mechabellum.${domain}";
  apiHost = "127.0.0.1";
  apiPort = 8010;

  mechPackages = inputs.mechabellum-replay-analysis.packages.${system};

  mechabellumBackend = pkgs.python312.withPackages (_: [
    mechPackages.backend
  ]);

  mechabellumFrontend = mechPackages.frontend.overrideAttrs (_: {
    VITE_API_BASE_URL = "https://${mechDomain}";
    VITE_PUBLIC_APP_URL = "https://${mechDomain}";
  });

  stateDir = "/var/lib/mechabellum";
  staticDir = "${stateDir}/static";
in {
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 root root -"
    "d ${stateDir}/replays 0750 root root -"
    "d ${stateDir}/analysis_batches 0750 root root -"
    "d ${stateDir}/analysis_reports 0750 root root -"
    "d ${staticDir} 0755 root root -"
  ];

  systemd.services.mechabellum-api = {
    description = "Mechabellum Replay Analysis API";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig = {
      ConditionPathExists = [
        "${staticDir}/unit_id_to_name.json"
        "${staticDir}/unit_footprints.json"
      ];
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = ''
        ${mechabellumBackend}/bin/uvicorn \
          mechabellum_replay.backend.app:app \
          --host ${apiHost} \
          --port ${builtins.toString apiPort}
      '';
      WorkingDirectory = stateDir;
      StateDirectory = "mechabellum";
      Restart = "always";
      RestartSec = "5s";
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ stateDir ];
    };
    environment = {
      DATA_DIR = stateDir;
      STATIC_DATA_DIR = staticDir;
      CORS_ALLOWED_ORIGINS = "https://${mechDomain}";
    };
  };

  systemd.services.mechabellum-worker = {
    description = "Mechabellum Replay Analysis worker";
    after = [ "network-online.target" "mechabellum-api.service" ];
    wants = [ "network-online.target" "mechabellum-api.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig = {
      ConditionPathExists = [
        "${staticDir}/unit_id_to_name.json"
        "${staticDir}/unit_footprints.json"
      ];
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = ''
        ${mechabellumBackend}/bin/python -m mechabellum_replay.backend.worker
      '';
      WorkingDirectory = stateDir;
      StateDirectory = "mechabellum";
      Restart = "always";
      RestartSec = "5s";
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ stateDir ];
    };
    environment = {
      DATA_DIR = stateDir;
      STATIC_DATA_DIR = staticDir;
    };
  };

  services.nginx.virtualHosts."${mechDomain}" = sslOpts // {
    forceSSL = true;
    root = mechabellumFrontend;

    locations."/api/" = {
      proxyPass = "http://${apiHost}:${builtins.toString apiPort}/api/";
      extraConfig = ''
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };

    locations."/" = {
      tryFiles = "$uri $uri/ /index.html";
    };
  };

  warnings = [
    ''
      mechabellum.${domain} was enabled, but the upstream repo does not package
      data/static/unit_id_to_name.json or data/static/unit_footprints.json.
      Copy those files into ${staticDir} on the server before starting the API
      and worker units.
    ''
  ];
}
