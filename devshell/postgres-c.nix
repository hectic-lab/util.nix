{
  system,
  pkgs,
  self 
}: pkgs.mkShell {
  buildInputs = (with pkgs; [
      inotify-tools
      postgresql_15
    ]) ++ (with self.packages.${system}; [
      nvim-pager 
    ]) ++ (with pkgs; [
      gdb
      gcc
    ]);

  PAGER = "${self.packages.${system}.nvim-pager}/bin/pager";

  shellHook = ''
    export PATH=${pkgs.gcc}/bin:$PATH
    export PAGER="${self.packages.${system}.nvim-pager}/bin/pager"
  '';
}
