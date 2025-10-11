{ symlinkJoin, writeShellApplication, socat, dash, hectic, curl }:
let
  shell = "${dash}/bin/dash";
  bashOptions = [
    "errexit"
    "nounset"
  ];

  base64 = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "base64";
    runtimeInputs = [ ];
    text = builtins.readFile ./base64.sh;
  };

  # TODO: writeDashApplication
  probe = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "probe";
    runtimeInputs = [ socat dash probe-loop ];
    text = builtins.readFile ./probe.sh;
  };

  probe-loop = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "probe-loop";
    runtimeInputs = [ base64 ];
    text = builtins.readFile ./probe-loop.sh;
  };

  sentinel = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "sentinel";
    runtimeInputs = [ hectic.shellplot curl ];
    text = builtins.readFile ./sentinel.sh;
  };
in
symlinkJoin {
  name = "sentinèlla";
  paths = [ probe sentinel ];
}
