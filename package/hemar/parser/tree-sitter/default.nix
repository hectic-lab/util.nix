{ lib, stdenv, tree-sitter, nodejs, clang, makeWrapper }:

let
  # Compute hash of grammar.js to ensure rebuilds when grammar changes
  grammarHash = builtins.hashString "sha256" (builtins.readFile ./grammar.js);
  
  # Filter out generated files that should not be in the source
  sourceFilter = path: type:
    let
      baseName = baseNameOf path;
      # Filter out generated directories and files
      generated = baseName == "src" || 
                  baseName == "node_modules" ||
                  baseName == "build" ||
                  baseName == "target" ||
                  baseName == ".build" ||
                  baseName == "_obj" ||
                  baseName == ".venv" ||
                  baseName == "dist" ||
                  baseName == ".zig-cache" ||
                  baseName == "zig-cache" ||
                  baseName == "zig-out" ||
                  lib.hasSuffix ".so" baseName ||
                  lib.hasSuffix ".a" baseName ||
                  lib.hasSuffix ".wasm" baseName ||
                  baseName == "parser" ||
                  baseName == "parser.so";
    in !generated;
  
  grammarDrv = stdenv.mkDerivation {
    pname = "tree-sitter-hemar-grammar";
    version = "0.1.0-${lib.substring 0 8 grammarHash}";

    src = lib.cleanSourceWith {
      filter = sourceFilter;
      src = ./.;
    };

    nativeBuildInputs = [ tree-sitter nodejs ];

    buildPhase = ''
      export HOME="$TMPDIR"
      export XDG_CACHE_HOME="$TMPDIR/.cache"
      mkdir -p "$XDG_CACHE_HOME"

      export XDG_CONFIG_HOME="$TMPDIR/.config"

      mkdir -p "$XDG_CONFIG_HOME/tree-sitter"
      
      cat > "$XDG_CONFIG_HOME/tree-sitter/config.json" <<EOF
      { "parser-directories": ["$PWD"] }
      EOF

      # Clean any existing parser artifacts to ensure fresh build
      # Remove entire src directory if it exists (from local builds)
      rm -rf src parser parser.so *.so *.a

      tree-sitter generate

      tree-sitter build --output parser
    '';

    doCheck = true;

    checkPhase = ''
      export HOME="$TMPDIR"
      export XDG_CACHE_HOME="$TMPDIR/.cache"
      
      # Run tree-sitter tests
      tree-sitter test
    '';

    installPhase = ''
      mkdir -p $out/lib
      mkdir -p $out/parser
      mkdir -p $out/share/tree-sitter/grammars

      cp parser $out/lib/hemar.so

      mkdir -p $out/share/tree-sitter/grammars/hemar
      cp -r src grammar.js package.json queries tree-sitter.json $out/share/tree-sitter/grammars/hemar/ 2>/dev/null || true
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
      --set TREE_SITTER_GRAMMAR_PATH "${grammarDrv}/share/tree-sitter/grammars" \
      --chdir "${grammarDrv}/parser"

    # Create hemar-parser wrapper that runs tree-sitter-hemar parse
    makeWrapper $bin/bin/tree-sitter-hemar $bin/bin/hemar-parser \
      --add-flags "parse"
  '';

  meta = with lib; {
    description = "Tree-sitter grammar for Hemar templating language";
    homepage = "https://github.com/yukkop/util.nix";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
