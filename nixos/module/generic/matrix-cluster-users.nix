{
  inputs,
  flake,
  self,
}: {
  config,
  ...
}: {
  hectic.generic.matrix-cluster.users = {
    yukkop = {
      passwordFile = config.sops.secrets."matrix/users/yukkop/password".path;
      admin = true;
    };
    liquiz = {
      passwordFile = config.sops.secrets."matrix/users/liquiz/password".path;
    };
    vismajor = {
      passwordFile = config.sops.secrets."matrix/users/vismajor/password".path;
    };
    lvgkcfjl = {
      passwordFile = config.sops.secrets."matrix/users/lvgkcfjl/password".path;
    };
  };

  sops.secrets."matrix/users/yukkop/password" = {
    key      = "matrix/users/yukkop/password";
    owner    = "matrix-synapse";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };

  sops.secrets."matrix/users/liquiz/password" = {
    key      = "matrix/users/liquiz/password";
    owner    = "matrix-synapse";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };

  sops.secrets."matrix/users/vismajor/password" = {
    key      = "matrix/users/vismajor/password";
    owner    = "matrix-synapse";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };

  sops.secrets."matrix/users/lvgkcfjl/password" = {
    key      = "matrix/users/lvgkcfjl/password";
    owner    = "matrix-synapse";
    sopsFile = "${flake}/sus/matrix-cluster.yaml";
  };
}
