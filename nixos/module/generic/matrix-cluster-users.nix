{
  inputs,
  flake,
  self,
}: {
  lib,
  config,
  ...
}: let
  userNames = [
    "yukkop"
    "liquiz"
    "vismajor"
    "lvgkcfjl"
    "MrAlex0O"
    "Антоша"
  ];

  adminNames = [ "yukkop" ];
in {
  hectic.generic.matrix-cluster.users = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = {
        passwordFile = config.sops.secrets."matrix/users/${name}/password".path;
      } // lib.optionalAttrs (builtins.elem name adminNames) {
        admin = true;
      };
    }) userNames
  );

  sops.secrets = builtins.listToAttrs (
    map (name: {
      name = "matrix/users/${name}/password";
      value = {
        key      = "matrix/users/${name}/password";
        owner    = "matrix-synapse";
        sopsFile = "${flake}/sus/matrix-cluster.yaml";
      };
    }) userNames
  );
}
