{ postgresql, pkg-config, patchelf }:
buildPostgresqlExtension { inherit postgresql; } {
  pname = "hemar";
  version = "0.1";
  src = ./.;

  nativeBuildInputs = [pkg-config c-hectic];

  dontShrinkRPath = true;

  postFixup = ''
    echo ">>> postFixup running..."
    ${patchelf}/bin/patchelf --set-rpath ${c-hectic}/lib $out/lib/hemar.so
  '';

  preInstall = ''mkdir $out'';
};