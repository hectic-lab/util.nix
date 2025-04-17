{
  stdenv,
  gcc,
  lib,
  bash,
  inotify-tools,
}:
stdenv.mkDerivation {
  pname = "hectic";
  version = "1.0";
  src = ./.;
  doCheck = true;

  nativeBuildInputs = [gcc inotify-tools];

  buildPhase = ''
    ls
    ${bash}/bin/sh ./make.sh build
  '';

  checkPhase = ''
    ${bash}/bin/sh ./make.sh check
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include
    cp target/libhectic.a $out/lib/
    cp hectic.h $out/include/
  '';

  meta = {
    description = "hectic";
    license = lib.licenses.mit;
  };
}
