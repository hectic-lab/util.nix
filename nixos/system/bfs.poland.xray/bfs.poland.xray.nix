{
  inputs,
  flake,
  self,
}: {
  lib,
  pkgs,
  modulesPath,
  config,
  ...
}: {
  imports = [
    self.nixosModules.xray-system
    self.nixosModules.matrix-cluster
  ];

  hectic.generic.xray-system = {
    enable          = true;
    defaultSopsFile = ../../../sus/bfs.xray.yaml;
  };

  hectic.generic.matrix-cluster = {
    enable        = true;
    role          = "standby";
    matrixDomain  = "accord.tube";
    signingKeyFile = config.sops.secrets."matrix/signing-key".path;
    objectStorage.s3 = {
      bucket          = "matrix-hectic-lab";
      regionName      = "hel1";
      endpointUrl     = "https://hel1.your-objectstorage.com";
      credentialsFile = config.sops.secrets."matrix/object-storage/credentials".path;
    };
    replication = {
      peerHost     = "128.140.75.58";
      passwordFile = config.sops.secrets."matrix/postgres-replication-password".path;
    };
    acme = {
      enable                  = true;
      porkbunApiKeyFile       = config.sops.secrets."matrix/porkbun-api-key".path;
      porkbunSecretApiKeyFile = config.sops.secrets."matrix/porkbun-secret-api-key".path;
    };
  };

  sops.secrets."matrix/signing-key" = {
    key      = "matrix/signing-key";
    owner    = "matrix-synapse";
    mode     = "0400";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };
  sops.secrets."matrix/postgres-replication-password" = {
    key      = "matrix/postgres-replication-password";
    owner    = "postgres";
    mode     = "0400";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };
  sops.secrets."matrix/object-storage/credentials" = {
    key      = "matrix/object-storage/credentials";
    owner    = "matrix-synapse";
    mode     = "0400";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };
  sops.secrets."matrix/porkbun-api-key" = {
    key      = "matrix/porkbun-api-key";
    mode     = "0400";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };
  sops.secrets."matrix/porkbun-secret-api-key" = {
    key      = "matrix/porkbun-secret-api-key";
    mode     = "0400";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };
}
