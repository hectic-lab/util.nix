{ system, inputs, self, pkgs, flake }: 
  (import ./package { inherit system inputs self pkgs; })

