{ stdenv, gcc, lib, hectic }:

stdenv.mkDerivation {
  pname = "hmpl";
  version = "1.0";
  src = ./.;
  doCheck = true;

  buildInputs = [ hectic ];

  buildPhase = ''
    mkdir -p target

    echo "# Build library"
    ${gcc}/bin/cc -Wall -Wextra -g \
      -std=c99 \
      -pedantic -fsanitize=address -c hmpl.c \
      -lhectic \
      -o target/hmpl.o
    ${gcc}/bin/ar rcs target/libhmpl.a target/hmpl.o

    echo "# Build app"
    ${gcc}/bin/cc -Wall -Wextra -g \
      -pedantic -fsanitize=address main.c \
      -Ltarget -lhmpl \
      -lhectic -o target/hmpl
  '';

  checkPhase = ''
    mkdir -p target/test
    for test_file in test/*.c; do
      exe="target/test/$(basename ''${test_file%.c})"
      ${gcc}/bin/cc -Wall -Wextra -g -pedantic \
        -fsanitize=address -I. "$test_file" \
	-Ltarget -lhmpl -lhectic -o "$exe"
      "$exe"
    done
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib $out/include
    cp target/hmpl $out/bin/hmpl
    cp target/libhmpl.a $out/lib/
    cp hmpl.h $out/include/hmpl.h
  '';

  meta = {
    description = "hectic";
    license = lib.licenses.mit;
  };
}
