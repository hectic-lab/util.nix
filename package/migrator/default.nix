{ dash, hectic, sqlite, postgresql_17 }:
let
  shell = "${dash}/bin/dash";
  bashOptions = [
    "errexit"
    "nounset"
  ];

  migrator = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "migrator";
    runtimeInputs = [ sqlite postgresql_17 ];

    text = ''
      ${builtins.readFile hectic.helpers.posix-shell.log}
      ${builtins.readFile ./migrator.sh}
    '';
  };
in
migrator
