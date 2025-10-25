{ symlinkJoin, writeTextFile, socat, dash, hectic, curl, gawk, jq }:
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

  probe = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "probe";
    runtimeInputs = [ socat dash router ];
    text = builtins.readFile ./probe.sh;
  };

  router = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "router";
    runtimeInputs = [ base64 gawk ];
    text = ''
      ${builtins.readFile ./log.sh}
      ${builtins.readFile ./colors.sh}
      ${builtins.readFile ./router.sh}
    '';
  };

  sentinel = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "sentinel";
    runtimeInputs = [ hectic.shellplot curl jq ];

    text = ''
      ${builtins.readFile ./log.sh}
      ${builtins.readFile ./colors.sh}
      ${builtins.readFile ./sentinel.sh}
    '';
  };
in
symlinkJoin {
  name = "sentinèlla";
  paths = [ probe sentinel ];
}
