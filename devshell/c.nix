{
  system,
  pkgs,
  self 
}: pkgs.mkShell {
  buildInputs = (with pkgs; [
      inotify-tools
      gdb
      gcc
    ]) ++ (with self.packages.${system}; [
      c-hectic
      nvim-pager
      watch
    ]);

    PAGER = "${self.packages.${system}.nvim-pager}/bin/pager";
  }
