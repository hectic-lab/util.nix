{ lib
, stdenv
, makeWrapper
, dash
, yq-go
, tree-sitter
, hectic
}:

stdenv.mkDerivation {
  pname = "hemar-renderer";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ dash yq-go tree-sitter ];

  dontBuild = true;

  doCheck = true;

  checkPhase = ''
    export HOME="$TMPDIR"
    export PATH="${lib.makeBinPath [ dash yq-go tree-sitter hectic.hemar-parser ]}:$PATH"
    
    patchShebangs ./hemar-renderer.sh ./test/lauch.sh
    
    ${dash}/bin/dash ./test/lauch.sh
  '';

  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/share/hemar/examples
    
    cp ./hemar-renderer.sh $out/bin/hemar-renderer
    chmod +x $out/bin/hemar-renderer
    
    patchShebangs $out/bin/hemar-renderer
    
    wrapProgram $out/bin/hemar-renderer \
      --prefix PATH : ${lib.makeBinPath [ dash yq-go tree-sitter hectic.hemar-parser ]}
  '';

  meta = with lib; {
    description = "Renderer for the Hemar templating language";
    homepage = "https://github.com/yukkop/util.nix";
    license = licenses.mit;
    platforms = platforms.unix;
    maintainers = [ ];
  };
}

