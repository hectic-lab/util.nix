{pkgs, ...}: let
  name = "printobstacle";
in
  pkgs.writeShellScriptBin "${name}" ''
    printf "%s%s%s\n" "''${RED}" "$*" "''${RESET}"
  ''
