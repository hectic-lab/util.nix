{ symlinkJoin, writeShellApplication, socat, dash, hectic, curl }:
let
  # TODO: writeDashApplication
  probe = writeShellApplication {
    name = "probe";
    runtimeInputs = [ socat dash probe-loop ];
    text = builtins.readFile ./probe.sh;
  };

  probe-loop = writeShellApplication {
    name = "probe-loop";
    runtimeInputs = [ ];
    text = builtins.readFile ./probe-loop.sh;
  };

  sentinel = writeShellApplication {
    name = "sentinel";
    runtimeInputs = [ hectic.shellplot curl ];
    text = builtins.readFile ./sentinel.sh;
  };
in
symlinkJoin {
  name = "sentinèlla";
  paths = [ probe sentinel ];
}
