{ self, system, pkgs }:
{
  writers = pkgs.callPackage ./writer { };
}
