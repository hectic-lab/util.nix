{ pkgs, ... }:
let 
  writers = pkgs.callPackage ./writer  { };
in {
  helpers = pkgs.callPackage ./helper { };
  # NOTE(yukkop): duplicate writers in root of legacyPackages and writers due nixpkgs legacyPackages consistency
  writers = writers;
} // writers
