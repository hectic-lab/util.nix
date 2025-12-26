{ lib, stdenv, tree-sitter, nodejs, clang, makeWrapper }:

stdenv.mkDerivation {
  pname = "tree-sitter-hemar";
  version = "0.1.0";

  src = ./.;

  # Multiple outputs
  outputs = [ "out" "bin" ];

  nativeBuildInputs = [ tree-sitter nodejs clang makeWrapper ];

  buildPhase = ''
    export HOME="$TMPDIR"
    export XDG_CACHE_HOME="$TMPDIR/.cache"
    mkdir -p "$XDG_CACHE_HOME"

    # Generate parser from grammar
    tree-sitter generate

    # Build the shared library
    tree-sitter build --output parser
  '';

  installPhase = ''
    # Install to $out - tree-sitter files for neovim and other uses
    mkdir -p $out/lib
    mkdir -p $out/parser
    mkdir -p $out/share/tree-sitter/grammars

    # Install the parser library
    cp parser $out/lib/hemar.so

    # Also install to tree-sitter standard location
    mkdir -p $out/share/tree-sitter/grammars/hemar
    cp -r src grammar.js package.json queries $out/share/tree-sitter/grammars/hemar/
    cp parser $out/share/tree-sitter/grammars/hemar.so

    # Install grammar files for reference
    cp -r . $out/parser/

    # Install to $bin - wrapper script for tree-sitter CLI
    mkdir -p $bin/bin
    
    # Create a wrapper script that includes all necessary dependencies
    makeWrapper ${tree-sitter}/bin/tree-sitter $bin/bin/tree-sitter-hemar \
      --prefix PATH : ${lib.makeBinPath [ nodejs clang ]}
    
    # Wrap the parse script with necessary PATH
    mv $bin/bin/tree-sitter-hemar-parse $bin/bin/.tree-sitter-hemar-parse-unwrapped
    makeWrapper $bin/bin/.tree-sitter-hemar-parse-unwrapped $bin/bin/tree-sitter-hemar-parse \
      --prefix PATH : ${lib.makeBinPath [ nodejs clang ]}
  '';

  meta = with lib; {
    description = "Tree-sitter grammar for Hemar templating language";
    homepage = "https://github.com/yukkop/util.nix";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
