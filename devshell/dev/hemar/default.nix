{ pkgs, ... }: pkgs.mkShell {
  buildInputs = (with pkgs; [
    dash
    (pkgs.writeShellScriptBin "letest" ''
      ${pkgs.dash}/bin/dash ${./test.sh} "$@"
    '')
  ]);
}
