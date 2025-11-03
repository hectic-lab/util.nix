{ dash, hectic }: let
  shell = "${dash}/bin/dash";
  bashOptions = [
    "errexit"
    "nounset"
  ];
in {
  log = hectic.writeDash "log.sh" ''
    ${builtins.readFile ./colors.sh}
    ${builtins.readFile ./log.sh}
  '';
  colors = hectic.writeDash "colors.sh" ''
    ${builtins.readFile ./colors.sh}
  '';
}
