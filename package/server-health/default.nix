{ writeShellScriptBin, socat, bash }:
writeShellScriptBin "server-health" ''
  ${socat}/bin/socat -T5 -t5 TCP-LISTEN:''${PORT:-5988},reuseaddr,fork EXEC:"${bash}/bin/sh ${./server-health.sh}"
''
