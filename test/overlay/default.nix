{ flake, inputs, self, pkgs, system, ... }: pkgs.runCommand "overlay-hectic-env"
{
  nativeBuildInputs = [ ];
  buildInputs = [ ];
} ''
  ${builtins.readFile self.legacyPackages.${system}.helpers.posix-shell.log}

  # test target
  . ${flake}/overlay/hectic-env.sh

  # tests
  . ${./hectic-env.sh}
''
