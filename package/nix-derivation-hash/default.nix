{
  writeShellScriptBin,
  bash,
  nix,
}: let
  # Use folder name as name of this system
  name = builtins.baseNameOf ./.;
in writeShellScriptBin name /* sh */ ''
  set -a
  BIN_NIX_HASH="${nix}/bin/nix-hash"
  set +a
  ${bash}/bin/sh ${./${name}.sh} "$@"
''
