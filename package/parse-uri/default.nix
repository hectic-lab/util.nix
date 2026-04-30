{ stdenv, gcc, libpq, lib, bash }:

stdenv.mkDerivation {
  pname = "parse-uri";
  version = "1.0";

  src = ./.;
  doCheck = false;

  nativeBuildInputs = [ gcc ];
  buildInputs = [ libpq ];

  INCLUDES = "-I${libpq.dev}/include";
  LDFLAGS = "-L${libpq.out}/lib -lpq";

  buildPhase = ''
    ${bash}/bin/sh ./make.sh build
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp target/parse-uri $out/bin/
  '';

  meta = {
    description = "parse-uri";
    license = lib.licenses.mit;
  };
}
