{ system, inputs, self, pkgs }:   (import ./migrator { inherit system inputs self pkgs; })
