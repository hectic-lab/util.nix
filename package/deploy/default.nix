{ symlinkJoin, writeTextFile, socat, dash, hectic, curl, gawk, jq }:
let
  shell = "${dash}/bin/dash";
  bashOptions = [
    "errexit"
    "nounset"
  ];

  deploy = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "deploy";
    runtimeInputs = [];

    text = builtins.readFile ./deploy.sh;
  };
in
symlinkJoin {
  name = "deploy";
  paths = [ deploy ];
}
