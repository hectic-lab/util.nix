{ stdenv, gcc, lib, c-hectic, bash }:

stdenv.mkDerivation {
  pname = "hmpl";
  version = "1.0";
  src = ./.;
  doCheck = true;

  buildInputs = [ c-hectic ];
  nativeBuildInputs = [ gcc ];

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
    description = "hmpl";
    license = lib.licenses.mit;
  };
}
