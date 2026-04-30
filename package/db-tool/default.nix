{ dash, hectic, postgresql_17, neovim, openssh, coreutils, gawk, lib, runCommand }:
let
  shell = "${dash}/bin/dash";

  hecticInheritanceSqlPath = ./sql/hectic-inheritance.sql;

  hecticInheritance = runCommand "hectic-inheritance" { } ''
    mkdir -p "$out/share/hectic"
    cp ${hecticInheritanceSqlPath} "$out/share/hectic/hectic-inheritance.sql"
  '';

  mkDatabase =
    { postgresql ? postgresql_17 }:
    hectic.writeShellApplication {
      inherit shell;
      bashOptions = [
        "errexit"
        "nounset"
      ];
      # SC2209: false positive — PAGER_OR_CAT=cat stores the string "cat" intentionally
      excludeShellChecks = [ "SC2209" ];
      name = "database";
      runtimeInputs = [ hectic.migrator hectic.parse-uri postgresql neovim openssh coreutils gawk ];

      text = ''
        ${builtins.readFile hectic.helpers.posix-shell.log}
        ${builtins.readFile hectic.helpers.posix-shell.change_namespace}
        ${builtins.readFile hectic.helpers.posix-shell.quote}
        ${builtins.readFile hectic.helpers.posix-shell.pager_or_cat}
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
        HECTIC_INHERITANCE_SQL_DEFAULT="${hecticInheritance}/share/hectic/hectic-inheritance.sql"
        export HECTIC_INHERITANCE_SQL_DEFAULT
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
