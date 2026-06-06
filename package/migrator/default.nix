{ dash, hectic, sqlite, postgresql_17, gawk, self }:
let
  shell = "${dash}/bin/dash";
  bashOptions = [
    "errexit"
    "nounset"
  ];

  applyBundle = self.lib.hectic.applyBundleScript;

  migrator = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "migrator";
    runtimeInputs = [ sqlite postgresql_17 gawk ];

    text = ''
      ${builtins.readFile hectic.helpers.posix-shell.log}
      ${applyBundle}
      ${builtins.readFile ./migrator.sh}
    '';
  };
in
migrator
