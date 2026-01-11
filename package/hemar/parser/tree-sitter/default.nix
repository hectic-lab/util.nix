{ lib, stdenv, rustPlatform, tree-sitter, nodejs, clang, makeWrapper, fetchFromGitHub, llvmPackages, pkg-config, glibc }:

let
  grammarHash = builtins.hashString "sha256" (builtins.readFile ./grammar.js);

  grammarDrv = stdenv.mkDerivation {
    pname = "tree-sitter-hemar-grammar";
    version = "0.1.0-${lib.substring 0 8 grammarHash}";

    src = lib.cleanSourceWith {
      src = ./.;
    };

    nativeBuildInputs = [ (tree-sitter.overrideAttrs (old: rec {
      version = "0.26.0";
      src = fetchFromGitHub {
        owner = "tree-sitter";
        repo = "tree-sitter";
        tag = "v${version}";
        hash = "sha256-M7CcQiWNSL8HILk4R6ShEGNnr4u5+hAZ8r3/a8e9jvw=";
        fetchSubmodules = true;
      };
    
      # IMPORTANT: nixpkgs likely sets cargoDeps; override it or you'll keep 0.25.10-vendor
      cargoDeps = rustPlatform.fetchCargoVendor {
        inherit src;
        hash = "sha256-Epj9Z69p5PjVjZhZZZ0XkcvXJ5f9ls5PDJKC7oufLF8=";
      };

      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        clang
        llvmPackages.libclang
        stdenv.cc.cc
        glibc.dev
      ];

      LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";

      # make sure clang sees the nix cc include paths
      BINDGEN_EXTRA_CLANG_ARGS = toString [
        "-isystem" "${stdenv.cc.cc}/include"
        "-isystem" "${glibc.dev}/include"
        "-isystem" "${glibc.dev}/include/gnu"
        "-I" "${stdenv.cc.cc}/lib/gcc/${stdenv.hostPlatform.config}/${stdenv.cc.cc.version}/include"
        "-I" "${stdenv.cc.cc}/lib/gcc/${stdenv.hostPlatform.config}/${stdenv.cc.cc.version}/include-fixed"
      ];

      patches = [];
    })) nodejs ];

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
      rm -rf src

      echo ls:
      ls

      tree-sitter generate
      tree-sitter build --output parser

      ls -la parser

      set +e
      echo greps:
      cat src/grammar.json | grep text
      cat src/grammar.json | grep zalupa
      echo greps 2:
      cat grammar.js | grep text
      cat grammar.js | grep zalupa
      set -e
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

      mkdir -p $out/share/tree-sitter/grammars/tree-sitter-hemar
      cp -r src grammar.js package.json queries tree-sitter.json $out/share/tree-sitter/grammars/tree-sitter-hemar/ 2>/dev/null || true
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
    mkdir -p $bin/bin/bin
    makeWrapper ${tree-sitter}/bin/tree-sitter $bin/bin/hemar-parser \
  --add-flags "parse -- source.hemar"

  '';

  meta = with lib; {
    description = "Tree-sitter grammar for Hemar templating language";
    homepage = "https://github.com/yukkop/util.nix";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
