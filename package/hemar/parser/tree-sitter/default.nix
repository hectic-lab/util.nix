{ lib, stdenv, tree-sitter, nodejs, clang, makeWrapper }:

let
  grammarDrv = stdenv.mkDerivation {
    pname = "tree-sitter-hemar-grammar";
    version = "0.1.0";

    src = ./.;

    nativeBuildInputs = [ tree-sitter nodejs ];

    buildPhase = ''
      export HOME="$TMPDIR"
      export XDG_CACHE_HOME="$TMPDIR/.cache"
      mkdir -p "$XDG_CACHE_HOME"

      tree-sitter generate

      tree-sitter build --output parser
    '';

    installPhase = ''
      mkdir -p $out/lib
      mkdir -p $out/parser
      mkdir -p $out/share/tree-sitter/grammars

      cp parser $out/lib/hemar.so

      mkdir -p $out/share/tree-sitter/grammars/hemar
      cp -r src grammar.js package.json queries $out/share/tree-sitter/grammars/hemar/
      cp parser $out/share/tree-sitter/grammars/hemar.so

      cp -r . $out/parser/
    '';
  };
in
stdenv.mkDerivation {
  pname = "tree-sitter-hemar";
  version = "0.1.0";

  # Multiple outputs
  outputs = [ "out" "bin" ];

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    # Install to $out - tree-sitter files
    mkdir -p $out
    ln -s ${grammarDrv}/lib $out/lib
    ln -s ${grammarDrv}/parser $out/parser
    ln -s ${grammarDrv}/share $out/share

    # Install to $bin - wrapper script for tree-sitter CLI
    mkdir -p $bin/bin
    
    makeWrapper ${tree-sitter}/bin/tree-sitter $bin/bin/tree-sitter-hemar \
      --prefix PATH : ${lib.makeBinPath [ nodejs clang ]} \
      --set TREE_SITTER_GRAMMAR_PATH "${grammarDrv}/share/tree-sitter/grammars"
  '';

  meta = with lib; {
    description = "Tree-sitter grammar for Hemar templating language";
    homepage = "https://github.com/yukkop/util.nix";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
