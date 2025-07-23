{
  writeShellScriptBin,
  bash,
}: let
  # Use folder name as name of this system
  name = builtins.baseNameOf ./.;
in writeShellScriptBin name /* sh */ ''
  ${bash}/bin/sh ${./${name}.sh} "$@"
''
