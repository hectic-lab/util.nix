{ dash, hectic, symlinkJoin }:
let
  shell = "${dash}/bin/dash";
  bashOptions = [
    "errexit"
    "nounset"
  ];

  test = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "hemar-test";
    runtimeInputs = [ ];

    text = ''
      WORKSPACE=${./.}
      ${builtins.readFile hectic.helpers.posix-shell.log}
      ${builtins.readFile ./test.sh}
    '';
  };

  hemar = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "hemar";
    runtimeInputs = [ ];

    text = ''
      WORKSPACE=${./.}
      ${builtins.readFile hectic.helpers.posix-shell.log}
      ${builtins.readFile ./hemar.sh}
    '';
  };
in
symlinkJoin {
  name = "hemar";
  paths = [ hemar test ];
}
