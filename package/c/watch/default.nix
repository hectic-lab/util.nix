{ stdenv, gcc, lib, hectic, bash }:

stdenv.mkDerivation {
  pname = "watch";
  version = "1.0";
  src = ./.;
  doCheck = true;

  nativeBuildInputs = [ gcc gdb ];

  buildPhase = ''
    ${bash}/bin/sh ./make.sh build
  '';

  checkPhase = ''
    ${bash}/bin/sh ./make.sh check
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib $out/include
    cp target/hmpl $out/bin/hmpl
    cp target/libhmpl.a $out/lib/
    cp hmpl.h $out/include/hmpl.h
  '';

  meta = {
    description = "watch";
    license = lib.licenses.mit;
  };
}