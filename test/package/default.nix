{ system, inputs, self, pkgs }:
  (import ./migrator      { inherit system inputs self pkgs; }) //
  (import ./hemar         { inherit system inputs self pkgs; }) //
  (import (./. + "/sentinèlla") { inherit system inputs self pkgs; }) //
  (import ./db-tool       { inherit system inputs self pkgs; }) //
  (import ./linux-devshell { inherit system inputs self pkgs; })
