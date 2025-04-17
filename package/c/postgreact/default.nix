{
  lib,
  stdenv,
  fetchFromGitHub,
  curl,
  postgresql,
  buildPostgresqlExtension,
}:
buildPostgresqlExtension rec {
  pname = "postgreact";
  version = "1.0";

  buildInputs = [
  ];

  EXTENSION = pname;
  EXTENSION_VERSION = version;

  src = ./.;

  env.NIX_CFLAGS_COMPILE = "-Wno-error";

  meta = with lib; {
    description = "PostgreSQL extension for simple templating.";
    homepage = "https://github.com/hectic-lab/util.nix";
    license = licenses.asl20;
    platforms = postgresql.meta.platforms;
    maintainers = with maintainers; [];
  };
}
