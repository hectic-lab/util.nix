{ stdenv, gcc, lib, bash, gdb }:

stdenv.mkDerivation {
  pname = "watch";
  version = "1.0";
  src = ./.;
  doCheck = false;

  nativeBuildInputs = [ gcc gdb ];

  buildPhase = ''
    ${bash}/bin/sh ./make.sh build
  '';

  checkPhase = ''
    ${bash}/bin/sh ./make.sh check
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp target/watch $out/bin/watch
  '';

  meta = {
    description = "watch";
    license = lib.licenses.mit;
  };
}