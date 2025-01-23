# TODO: allow multiline
file: let
  envText = builtins.readFile file;
  envLines = builtins.split "\n" envText;
  lines = builtins.filter (line: (builtins.match "^.*=.*" line) != null) envLines;
  #attributes = builtins.listToAttrs (builtins.map (line: let
  #  parts = builtins.split "=" line;
  #  key = builtins.substring 0 (builtins.stringLength parts[0] - 3) parts[0]; # Remove "var" prefix
  #  value = parts[1];
  #in {
  #  name = key;
  #  value = value;
  #}) lines);
in {inherit envLines lines;}
