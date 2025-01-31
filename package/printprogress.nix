{ pkgs, ... }:
let
  name = "printprogress";
in
pkgs.writeShellScriptBin "${name}"  ''
  printf "%s%s%s\n" "''${YELLOW}" "$*" "''${RESET}" 
''
