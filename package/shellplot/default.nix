{ imagemagick, bash, writeShellScriptBin }:
writeShellScriptBin "shellplot" ''
  set -a
  BIN_CONVERT=${imagemagick}/bin/convert
  set +a
  ${bash}/bin/sh ${./shellplot.sh}
''
