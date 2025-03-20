{ stdenv, gcc, lib, libhectic }:

stdenv.mkDerivation {
  pname = "libhectic";
  version = "1.0";
  src = ./.;
  doCheck = true;

  buildInputs = [ libhectic ];

  buildPhase = ''
    mkdir -p target
    ${gcc}/bin/cc -Wall -Wextra -g \
      -pedantic -fsanitize=address -c hmpl.c \
      -l:libhectic.a -o target/libhectic.o
  '';

  checkPhase = '' '';

  installPhase = ''
    mkdir -p $out/lib $out/include
  '';

  meta = {
    description = "libhectic";
    license = lib.licenses.mit;
  };
}
