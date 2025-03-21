{ stdenv, gcc, lib, libhectic, cjson }:

stdenv.mkDerivation {
  pname = "hmpl";
  version = "1.0";
  src = ./.;
  doCheck = true;

  buildInputs = [ libhectic cjson ];

  buildPhase = ''
    mkdir -p target
    ${gcc}/bin/cc -Wall -Wextra -g \
      -pedantic -fsanitize=address hmpl.c \
      -l:libhectic.a -l:cjson -o target/hmpl
  '';

  checkPhase = '' '';

  installPhase = ''
    mkdir -p $out/bin
    cp target/hmpl $out/bin/hmpl
  '';

  meta = {
    description = "libhectic";
    license = lib.licenses.mit;
  };
}
