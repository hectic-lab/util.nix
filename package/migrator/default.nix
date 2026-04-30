{ dash, hectic, sqlite, postgresql_17, gawk, runCommand, self }:
let
  shell = "${dash}/bin/dash";
  bashOptions = [
    "errexit"
    "nounset"
  ];

  hecticVersionSqlFile = runCommand "hectic-version.sql" {
    text = self.lib.hectic.version.sql;
    passAsFile = [ "text" ];
  } ''cp "$textPath" "$out"'';

  hecticEnv = ''
    HECTIC_VERSION_SQL=${hecticVersionSqlFile}
    HECTIC_SECRET_SQL=${self.lib.hectic.secret.path}
    HECTIC_MIGRATION_SQL=${self.lib.hectic.migration.path}
    HECTIC_INHERITANCE_SQL=${self.lib.hectic.inheritance.path}
    export HECTIC_VERSION_SQL HECTIC_SECRET_SQL HECTIC_MIGRATION_SQL HECTIC_INHERITANCE_SQL
  '';

  applyBundle = builtins.readFile self.lib.hectic.applyBundleScript;

  migrator = hectic.writeShellApplication {
    inherit shell bashOptions;
    name = "migrator";
    runtimeInputs = [ sqlite postgresql_17 gawk ];

    text = ''
      ${builtins.readFile hectic.helpers.posix-shell.log}
      ${hecticEnv}
      ${applyBundle}
      ${builtins.readFile ./migrator.sh}
    '';
  };
in
migrator
