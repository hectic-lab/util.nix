{ pkgs }: let
 dev-help = pkgs.writeShellScriptBin "dev-help" /* sh */ ''
   printf '%s\n' \
   'phph'
 '';
in
pkgs.mkShell {
  buildInputs = [ dev-help ];
  nativeBuildInputs = [ pkgs.pkg-config ];

  # environment
  PAGER="${pkgs.hectic.nvim-pager}/bin/pager";
}
