{ pkgs }: let
 dev-help = pkgs.writeShellScriptBin "dev-help" /* sh */ ''
   printf '%s\n' \
   'phph'
 '';
 rustToolchain = pkgs.pkgsBuildHost.rust-bin.stable."1.87.0".default;
in
pkgs.mkShell {
  buildInputs = [ dev-help ];
  nativeBuildInputs = [ rustToolchain pkgs.pkg-config ];

  # environment
  PAGER="${pkgs.hectic.nvim-pager}/bin/pager";
}
