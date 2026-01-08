{ lib
, makeWrapper
, dash
, yq-go
, xmlstarlet
, tree-sitter
, hectic
}:

hectic.hectic-env.mkDerivation {
  pname = "hemar-renderer";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ dash yq-go xmlstarlet tree-sitter ];

  doCheck = true;

  buildPhase = ''
    hecticPatchInclude ${hectic.helpers.posix-shell.log} ./hemar-renderer.sh
    hecticPatchInclude ${hectic.helpers.posix-shell.log} ./test/lauch.sh

    patchShebangs ./hemar-renderer.sh ./test/lauch.sh
  '';

  checkPhase = ''
    export HOME="$TMPDIR"
    export PATH="${lib.makeBinPath [ dash yq-go xmlstarlet tree-sitter hectic.hemar-parser ]}:$PATH"
    
    ${dash}/bin/dash ./test/lauch.sh
  '';

  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/share/hemar/examples
    
    cp ./hemar-renderer.sh $out/bin/hemar-renderer
    chmod +x $out/bin/hemar-renderer
    
    wrapProgram $out/bin/hemar-renderer \
      --prefix PATH : ${lib.makeBinPath [ dash yq-go xmlstarlet tree-sitter hectic.hemar-parser ]}
  '';

  meta = with lib; {
    description = "Renderer for the Hemar templating language";
    homepage = "https://github.com/yukkop/util.nix";
    license = licenses.mit;
    platforms = platforms.unix;
    maintainers = [ ];
  };
}

