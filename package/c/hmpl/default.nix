{ stdenv, gcc, lib, hectic, bash }:

stdenv.mkDerivation {
  pname = "hmpl";
  version = "1.0";
  src = ./.;
  doCheck = true;

  buildInputs = [ hectic ];
  nativeBuildInputs = [ gcc ];

  buildPhase = ''
    ${bash}/bin/sh ./build.sh
  '';

  checkPhase = ''
    ${bash}/bin/sh ./check.sh
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
