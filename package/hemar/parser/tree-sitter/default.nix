{ lib, stdenv, tree-sitter, nodejs }:

stdenv.mkDerivation {
  pname = "tree-sitter-hemar";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ tree-sitter nodejs ];

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
  '';

  meta = with lib; {
    description = "Tree-sitter grammar for Hemar templating language";
    homepage = "https://github.com/yukkop/util.nix";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
