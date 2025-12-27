{ lib, hectic, dash, symlinkJoin, callPackage }: let
  tree-sitter-hemar = callPackage ./tree-sitter {};
in
symlinkJoin {
  name = "hemar-parser";
  paths = [ tree-sitter-hemar tree-sitter-hemar.bin ];
}
