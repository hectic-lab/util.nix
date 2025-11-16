{ symlinkJoin, dash, hectic }: let
  shell = "${dash}/bin/dash";
  bashOptions = [
    "errexit"
    "nounset"
  ];

  show-megumin = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "show-megumin";
    runtimeInputs = [ ];
    text = builtins.readFile ./show-megumin.sh;
  };
in
symlinkJoin {
  name = "sentinèlla";
  paths = [ show-megumin ];
}
