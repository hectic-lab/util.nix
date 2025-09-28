{ pkgs, ... }: pkgs.mkShell {
  buildInputs = (with pkgs; [
    dash
  ]);
}
