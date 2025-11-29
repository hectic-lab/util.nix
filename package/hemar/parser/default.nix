{ dash, hectic, symlinkJoin, yq-go }:
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
      # shellcheck disable=SC2034
      WORKSPACE=${./.}
      ${builtins.readFile hectic.helpers.posix-shell.log}
      ${builtins.readFile ./test.sh}
    '';
  };

  hemar = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "hemar";
    runtimeInputs = [ yq-go ];

    text = ''
      # shellcheck disable=SC2034
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
