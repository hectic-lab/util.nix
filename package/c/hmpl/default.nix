{ stdenv, gcc, lib, chectic, cjson }:

stdenv.mkDerivation {
  pname = "hmpl";
  version = "1.0";
  src = ./.;
  doCheck = true;

  buildInputs = [ chectic cjson ];

  buildPhase = ''
    mkdir -p target
    ${gcc}/bin/cc -Wall -Wextra -g \
      -pedantic -fsanitize=address hmpl.c \
      -lchectic -lcjson -o target/hmpl
  '';

  checkPhase = '' '';

  installPhase = ''
    mkdir -p $out/bin
    cp target/hmpl $out/bin/hmpl
  '';

  meta = {
    description = "chectic";
    license = lib.licenses.mit;
  };
}
