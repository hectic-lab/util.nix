{ stdenv, gcc, lib, chectic }:

stdenv.mkDerivation {
  pname = "hmpl";
  version = "1.0";
  src = ./.;
  doCheck = true;

  buildInputs = [ chectic ];

  buildPhase = ''
    mkdir -p target

    echo "# Build library"
    ${gcc}/bin/cc -Wall -Wextra -g \
      -std=c99 \
      -pedantic -fsanitize=address -c hmpl.c \
      -lchectic \
      -o target/hmpl.o
    ${gcc}/bin/ar rcs target/libhmpl.a target/hmpl.o

    echo "# Build app"
    ${gcc}/bin/cc -Wall -Wextra -g \
      -pedantic -fsanitize=address main.c \
      -Ltarget -lhmpl \
      -lchectic -o target/hmpl
  '';

  checkPhase = '' '';

  installPhase = ''
    mkdir -p $out/bin $out/lib $out/include
    cp target/hmpl $out/bin/hmpl
    cp target/libhmpl.a $out/lib/
    cp hmpl.h $out/include/hmpl.h
  '';

  meta = {
    description = "chectic";
    license = lib.licenses.mit;
  };
}
