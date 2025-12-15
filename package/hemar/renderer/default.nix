{ lib
, stdenv
, makeWrapper
, dash
, yq-go
, tree-sitter
, hemar-grammar
}:

stdenv.mkDerivation {
  pname = "hemar-renderer";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ dash yq-go tree-sitter ];

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/share/hemar/examples
    
    # Install renderer
    cp render.sh $out/bin/hemar-render
    chmod +x $out/bin/hemar-render
    
    # Install main entry point
    cp hemar $out/bin/hemar
    chmod +x $out/bin/hemar
    
    # Install examples
    cp -r examples/* $out/share/hemar/examples/
    
    # Patch shebangs
    patchShebangs $out/bin/hemar-render
    patchShebangs $out/bin/hemar
    
    # Wrap scripts to ensure dependencies are available
    # Also set TREE_SITTER_LIBDIR to find the hemar grammar
    wrapProgram $out/bin/hemar-render \
      --prefix PATH : ${lib.makeBinPath [ dash yq-go tree-sitter ]} \
      --set TREE_SITTER_LIBDIR ${hemar-grammar}/lib
    
    wrapProgram $out/bin/hemar \
      --prefix PATH : ${lib.makeBinPath [ dash yq-go tree-sitter ]} \
      --set TREE_SITTER_LIBDIR ${hemar-grammar}/lib
  '';

  meta = with lib; {
    description = "Renderer for the Hemar templating language";
    homepage = "https://github.com/yukkop/util.nix";
    license = licenses.mit;
    platforms = platforms.unix;
    maintainers = [ ];
  };
}

