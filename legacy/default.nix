{ self, system, pkgs }:
let 
  writers = pkgs.callPackage ./writer { };
in {
  # NOTE(yukkop): duplicate writers in root of legacyPackages and writers due nixpkgs legacyPackages consistency
  writers = writers;
} // writers
