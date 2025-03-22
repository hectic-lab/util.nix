{ stdenv, gcc, lib }:

stdenv.mkDerivation {
  pname = "hectic";
  version = "1.0";
  src = ./.;
  doCheck = true;

  buildPhase = ''
    mkdir -p target
    ${gcc}/bin/cc -Wall -Wextra -g \
      -std=c99 \
      -pedantic -fsanitize=address \
      -c hectic.c -o target/hectic.o
    ${gcc}/bin/ar rcs target/libhectic.a target/hectic.o
  '';

  checkPhase = ''
    mkdir -p target/test
    for test_file in test/*.c; do
      exe="target/test/$(basename ''${test_file%.c})"
      ${gcc}/bin/cc -Wall -Wextra -g -pedantic -fsanitize=address -I. "$test_file" -Ltarget -lhectic -o "$exe"
      "$exe"
    done
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include
    cp target/libhectic.a $out/lib/
    cp hectic.h $out/include/
  '';

  meta = {
    description = "libhectic";
    license = lib.licenses.mit;
  };
}
