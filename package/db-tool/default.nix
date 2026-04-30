{ dash, hectic, postgresql_17, neovim, openssh, coreutils, gawk, lib }:
let
  shell = "${dash}/bin/dash";

  database = hectic.writeShellApplication {
    inherit shell;
    bashOptions = [
      "errexit"
      "nounset"
    ];
    # SC2209: false positive — PAGER_OR_CAT=cat stores the string "cat" intentionally
    excludeShellChecks = [ "SC2209" ];
    name = "database";
    runtimeInputs = [ hectic.migrator hectic.parse-uri postgresql_17 neovim openssh coreutils gawk ];

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

  postgresInit = hectic.writeShellApplication {
    inherit shell;
    bashOptions = [ ];
    name = "postgres-init";
    runtimeInputs = [ postgresql_17 coreutils ];

    text = builtins.readFile ./postgres-init.sh;

    meta = {
      description = "Initialize local PostgreSQL instance";
      mainProgram = "postgres-init";
    };
  };

  postgresCleanup = hectic.writeShellApplication {
    inherit shell;
    bashOptions = [ ];
    name = "postgres-cleanup";
    runtimeInputs = [ postgresql_17 coreutils ];

    text = builtins.readFile ./postgres-cleanup.sh;

    meta = {
      description = "Clean up local PostgreSQL instance";
      mainProgram = "postgres-cleanup";
    };
  };
in
{
  "db-tool"          = database;
  "postgres-init"    = postgresInit;
  "postgres-cleanup" = postgresCleanup;
}
