{ symlinkJoin, writeTextFile, socat, dash, hectic, curl, gawk, jq, inetutils, getent, bind }:
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
    runtimeInputs = [ socat ];
    text = ''
      socat -T5 -t5 TCP-LISTEN:"''${PORT:-5988}",reuseaddr,fork EXEC:"${router}/bin/router",pipes
    '';
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

  watcher = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "watcher";
    runtimeInputs = [ curl jq gawk inetutils getent bind.dnsutils ];
    text = ''
      ${builtins.readFile ./log.sh}
      ${builtins.readFile ./colors.sh}
      ${builtins.readFile ./watcher.sh}
    '';
  };
in
symlinkJoin {
  name = "sentinèlla";
  paths = [ probe watcher ];
}
