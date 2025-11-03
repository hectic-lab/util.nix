  { dash, lib, writers }: name: argsOrScript:
  if lib.isAttrs argsOrScript && !lib.isDerivation argsOrScript then
    writers.makeScriptWriter (argsOrScript // { interpreter = "${lib.getExe dash}"; }) name
  else
    writers.makeScriptWriter { interpreter = "${lib.getExe dash}"; } name argsOrScript
