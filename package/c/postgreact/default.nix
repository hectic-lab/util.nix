{
  lib,
  stdenv,
  postgresql,
  ...
}: 

stdenv.mkDerivation {
  pname = "postgreact";
  version = "0.1";
  
  src = ./.;

  buildInputs = [
    postgresql
  ];

  buildPhase = ''
    mkdir -p target
    sh ./make.sh build
  '';

  installPhase = ''
    mkdir -p $out/lib/postgresql $out/share/postgresql/extension
    
    # Install compiled library
    install -m 755 -D target/postgreact.so $out/lib/postgresql/postgreact.so
    
    # Install control and SQL files
    install -m 644 -D postgreact.control $out/share/postgresql/extension/postgreact.control
    install -m 644 -D postgreact--0.1.sql $out/share/postgresql/extension/postgreact--0.1.sql
  '';

  meta = with lib; {
    description = "PostgreSQL extension for reactive functions";
    homepage = "https://github.com/yukkop/util.nix";
    license = licenses.mit;
    platforms = postgresql.meta.platforms;
    maintainers = with maintainers; [ ];
  };
} 
