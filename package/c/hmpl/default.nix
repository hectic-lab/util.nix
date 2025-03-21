{ stdenv, gcc, lib, libhectic }:

stdenv.mkDerivation {
  pname = "hmpl";
  version = "1.0";
  src = ./.;
  doCheck = true;

  buildInputs = [ libhectic ];

  buildPhase = ''
    mkdir -p target
    ${gcc}/bin/cc -Wall -Wextra -g \
      -pedantic -fsanitize=address hmpl.c \
      -l:libhectic.a -o target/hmpl
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
