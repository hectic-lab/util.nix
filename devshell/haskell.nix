{
  system,
  pkgs,
  self 
}: self.devShells.${system}.default
  // (pkgs.mkShell {
    buildInputs = [pkgs.stack];
  })
