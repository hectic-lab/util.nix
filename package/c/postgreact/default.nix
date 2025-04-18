{
  lib,
  stdenv,
  postgresql,
  ...
}:
stdenv.mkDerivation rec {
  pname = "postgreact";
  version = "1.0";

  src = ./.;

  USE_PGXS = 1;
  EXTENSION = pname;
  EXTENSION_VERSION = version;
  EXTENSION_COMMENT = meta.description;

  buildInputs = [
    postgresql
  ];

  buildPhase = ''make all'';

  installPhase = ''
    mkdir -p $out/lib/postgresql $out/share/postgresql/extension

    # Install compiled library
    install -m 755 -D postgreact.so $out/lib/postgresql/postgreact.so

    # Install control and SQL files
    install -m 644 -D postgreact.control $out/share/postgresql/extension/postgreact.control
    install -m 644 -D postgreact--${EXTENSION_VERSION}.sql $out/share/postgresql/extension/postgreact--${EXTENSION_VERSION}.sql
  '';

  meta = with lib; {
    description = "PostgreSQL extension for simple templating.";
    homepage = "https://github.com/yukkop/util.nix";
    license = licenses.asl20;
    platforms = postgresql.meta.platforms;
    maintainers = with maintainers; [];
  };
}
