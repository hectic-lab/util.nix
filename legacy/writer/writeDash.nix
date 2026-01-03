{ dash, lib, writers }: name: script:
(
  writers.makeScriptWriter {
    interpreter = "${lib.getExe dash}"; 
  } name script
).overrideAttrs (_: {
  # NOTE: some versions of nix do not allow `builtins.readFile` 
  #       for a derivation coz bla bla bla absolute path bla bla bla bla, hooy sasi 
  #       so better to use this variable
  scriptText = script;
})
