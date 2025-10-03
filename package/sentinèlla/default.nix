{ writeShellScriptBin, socat, dash }:
writeShellScriptBin "server-health" ''
  set +a
  LOOP_FILE=${./probe-loop.sh}
  socat() { ${socat}/bin/socat $@ }
  dash()  { ${dash}/bin/dash   $@ }
  set -a

  ${dash}/bin/dash ${./probe.sh}
''
