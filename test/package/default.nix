{ system, inputs, self, pkgs }:   
  (import ./migrator { inherit system inputs self pkgs; }) //
  (import ./hemar    { inherit system inputs self pkgs; })
