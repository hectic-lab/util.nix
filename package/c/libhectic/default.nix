{ stdenv, gcc, lib }:

stdenv.mkDerivation {
  pname = "libhectic";
  version = "1.0";
  src = ./.;
  doCheck = true;

  buildPhase = ''
    mkdir -p target
    ${gcc}/bin/cc -Wall -Wextra -g \
      -std=c99 \
      -pedantic -fsanitize=address \
      -c libhectic.c -o target/libhectic.o
    ${gcc}/bin/ar rcs target/libhectic.a target/libhectic.o
  '';

  checkPhase = ''
    mkdir -p target/test
    for test_file in test/*.c; do
      exe="target/test/$(basename ''${test_file%.c})"
      ${gcc}/bin/cc -Wall -Wextra -g -pedantic -fsanitize=address -I. "$test_file" -Ltarget -l:libhectic.a -o "$exe"
      "$exe"
    done
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include
    cp target/libhectic.a $out/lib/
    cp libhectic.h $out/include/
  '';

  meta = {
    description = "libhectic";
    license = lib.licenses.mit;
  };
}
