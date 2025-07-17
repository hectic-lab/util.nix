{
  system,
  pkgs,
  self 
}: pkgs.mkShell {
  buildInputs =
    (with self.packages.${system}; [
      nvim-alias
      #prettify-log
      nvim-pager
    ])
    ++ (with pkgs; [
      git
      jq
      yq-go
      curl
      (writeScriptBin "hemar-check" ''
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null vm-postgres 'zsh -c check'
      '')
    ]);

  # environment
  PAGER = "${self.packages.${system}.nvim-pager}/bin/pager";
}
