{
  domain,
  ...
}: {
  config,
  ...
}: let
  enteDomain = "ente.${domain}";
in {
  hectic.services.ente = {
    enable              = true;
    apiDomain           = "api.${enteDomain}";
    disableRegistration = false;

    domains = {
      accounts = "accounts.${enteDomain}";
      cast     = "cast.${enteDomain}";
      albums   = "albums.${enteDomain}";
      photos   = "photos.${enteDomain}";
    };

    smtp = {
      enable = true;
      host   = "mail.${domain}";
      email  = "security@${domain}";
    };

    storage = {
      bucket   = "ente-hectic-lab";
      endpoint = "https://hel1.your-objectstorage.com";
      region   = "hel1";
    };

    secrets = {
      encryptionKeyFile = config.sops.secrets."ente/key-encryption".path;
      hashKeyFile       = config.sops.secrets."ente/key-hash".path;
      jwtSecretFile     = config.sops.secrets."ente/jwt-secret".path;
      s3AccessKeyFile   = config.sops.secrets."ente/s3-access-key".path;
      s3SecretKeyFile   = config.sops.secrets."ente/s3-secret-key".path;
    };
  };
}
