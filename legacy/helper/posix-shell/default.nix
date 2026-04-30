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
  change_namespace = hectic.writeDash "change_namespace.sh" ''
    ${builtins.readFile ./change_namespace.sh}
  '';
  quote = hectic.writeDash "quote.sh" ''
    ${builtins.readFile ./quote.sh}
  '';
  pager_or_cat = hectic.writeDash "pager_or_cat.sh" ''
    ${builtins.readFile ./pager_or_cat.sh}
  '';
}
