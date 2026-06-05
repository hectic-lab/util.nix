{
  autoPatchelfHook,
  lib,
  gnutar,
  makeWrapper,
  stdenv,
  stdenvNoCC,
  fetchurl,
}:
let
  version = "4.1.0";
in
stdenvNoCC.mkDerivation {
  pname = "hiddify-core";
  inherit version;

  src = fetchurl {
    url = "https://github.com/hiddify/hiddify-core/releases/download/v${version}/hiddify-core-linux-amd64.tar.gz";
    hash = "sha256-efVXJbnBwLPK1GpF7e2zxb6D16YjbMHfqb14+zxofm8=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    gnutar
    makeWrapper
  ];

  buildInputs = [
    stdenv.cc.cc.lib
  ];

  unpackPhase = ''
    runHook preUnpack
    tar -xzf $src
    cd hiddify-core-linux-amd64
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib/hiddify-core $out/share/licenses/hiddify-core
    cp LICENSE.md $out/share/licenses/hiddify-core/LICENSE.md
    cp hiddify-core $out/lib/hiddify-core/
    cp libcronet.so $out/lib/hiddify-core/
    makeWrapper $out/lib/hiddify-core/hiddify-core $out/bin/hiddify-core \
      --set-default LD_LIBRARY_PATH "$out/lib/hiddify-core"
    ln -s $out/bin/hiddify-core $out/bin/hiddify-cli
    ln -s $out/bin/hiddify-core $out/bin/HiddifyCli
    runHook postInstall
  '';

  meta = {
    description = "Hiddify CLI core binary";
    homepage = "https://github.com/hiddify/hiddify-core";
    license = lib.licenses.gpl3Only;
    mainProgram = "hiddify-core";
    platforms = [ "x86_64-linux" ];
  };
}
