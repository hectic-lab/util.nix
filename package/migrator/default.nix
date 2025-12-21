{ dash, hectic, sqlite, postgresql_17, gawk }:
let
  shell = "${dash}/bin/dash";
  bashOptions = [
    "errexit"
    "nounset"
  ];

  migrator = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "migrator";
    runtimeInputs = [ sqlite postgresql_17 gawk ];

    text = ''
      ${builtins.readFile hectic.helpers.posix-shell.log}
      ${builtins.readFile ./migrator.sh}
    '';
  };
in
migrator
