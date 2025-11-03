{ dash, hectic }:
let
  shell = "${dash}/bin/dash";
  bashOptions = [
    "errexit"
    "nounset"
  ];

  migrator = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "migrator";
    runtimeInputs = [ ];

    text = ''
      ${builtins.readFile hectic.helpers.posix-shell.log}
      ${builtins.readFile ./migrator.sh}
    '';
  };
in
migrator
