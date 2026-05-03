{ dash, hectic, postgresql_17, neovim, openssh, coreutils, gawk, lib, runCommand, self }:
let
  shell = "${dash}/bin/dash";

  hecticInheritanceSqlPath = ../../lib/hook/sql/hectic-inheritance.sql;

  hecticInheritance = runCommand "hectic-inheritance" { } ''
    mkdir -p "$out/share/hectic"
    cp ${hecticInheritanceSqlPath} "$out/share/hectic/hectic-inheritance.sql"
  '';

  # Materialize the templated version SQL into the Nix store as a real file
  # so it can be passed by path to psql -f (alongside the static siblings).
  hecticVersionSqlFile = pkgs-writeText "hectic-version.sql" self.lib.hectic.version.sql;
  pkgs-writeText = name: text: runCommand name { inherit text; passAsFile = [ "text" ]; } ''
    cp "$textPath" "$out"
  '';

  hecticEnv = ''
    HECTIC_VERSION_SQL=${hecticVersionSqlFile}
    HECTIC_SECRET_SQL=${self.lib.hectic.secret.path}
    HECTIC_MIGRATION_SQL=${self.lib.hectic.migration.path}
    HECTIC_INHERITANCE_SQL=${self.lib.hectic.inheritance.path}
    export HECTIC_VERSION_SQL HECTIC_SECRET_SQL HECTIC_MIGRATION_SQL HECTIC_INHERITANCE_SQL
  '';

  applyBundle = builtins.readFile self.lib.hectic.applyBundleScript;

  mkDatabase =
    { postgresql ? postgresql_17 }:
    hectic.writeShellApplication {
      inherit shell;
      bashOptions = [
        "errexit"
        "nounset"
      ];
      excludeShellChecks = [ "SC2209" ];
      name = "database";
      runtimeInputs = [ hectic.migrator hectic.parse-uri postgresql neovim openssh coreutils gawk ];

      text = ''
        ${builtins.readFile hectic.helpers.posix-shell.log}
        ${builtins.readFile hectic.helpers.posix-shell.change_namespace}
        ${builtins.readFile hectic.helpers.posix-shell.quote}
        ${builtins.readFile hectic.helpers.posix-shell.pager_or_cat}
        ${builtins.readFile hectic.helpers.posix-shell.with_closed_fds}
        ${hecticEnv}
        ${applyBundle}
        ${builtins.readFile ./database.sh}
      '';

      meta = {
        description = "PostgreSQL development database management";
        mainProgram = "database";
      };
    };

  mkPostgresInit =
    { postgresql ? postgresql_17 }:
    hectic.writeShellApplication {
      inherit shell;
      bashOptions = [ ];
      name = "postgres-init";
      runtimeInputs = [ postgresql coreutils ];

      text = ''
        ${builtins.readFile hectic.helpers.posix-shell.with_closed_fds}
        ${builtins.readFile ./postgres-init.sh}
      '';


      meta = {
        description = "Initialize local PostgreSQL instance";
        mainProgram = "postgres-init";
      };
    };

  mkPostgresCleanup =
    { postgresql ? postgresql_17 }:
    hectic.writeShellApplication {
      inherit shell;
      bashOptions = [ ];
      name = "postgres-cleanup";
      runtimeInputs = [ postgresql coreutils ];

      text = builtins.readFile ./postgres-cleanup.sh;

      meta = {
        description = "Clean up local PostgreSQL instance";
        mainProgram = "postgres-cleanup";
      };
    };
in
{
  "db-tool"             = lib.makeOverridable mkDatabase { };
  "postgres-init"       = lib.makeOverridable mkPostgresInit { };
  "postgres-cleanup"    = lib.makeOverridable mkPostgresCleanup { };
  "hectic-inheritance"  = hecticInheritance;
}
