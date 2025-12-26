{ system, inputs, self, pkgs }:   
let
  prefixAttrs = prefix: set:
    pkgs.lib.mapAttrs'
      (name: value: {
        name = "${prefix}${name}";
        inherit value;
      })
      set;
in
  (prefixAttrs "migrator-" (import ./migrator { inherit system inputs self pkgs; })) //
  (prefixAttrs "hemar-"    (import ./hemar    { inherit system inputs self pkgs; }))
