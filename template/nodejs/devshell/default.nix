{ pkgs }:
let
  deps = with pkgs; [ nodejs ];

  depsText = builtins.concatStringsSep ", "
    (map (p: p.pname or p.name) deps);

  dev-help = pkgs.writeShellScriptBin "dev-help" /* sh */ ''
    printf '%s\n' \
      'Welcome to Nodejs devshell!' \
      'dependencies: ${depsText}' \
      'dev-help - this message'
  '';
in
pkgs.mkShell {
  buildInputs = [ dev-help ] ++ deps;
  nativeBuildInputs = [ pkgs.pkg-config ];

  shellHook = ''
    dev-help
  '';

  PAGER = "${pkgs.hectic.nvim-pager}/bin/pager";
}
