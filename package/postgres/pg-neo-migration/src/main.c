#include <stdio.h>
#include <stdlib.h>
#include "logger.c"
#include "macros.h"
#include <sys/stat.h>
#include <errno.h>    
#include <time.h>      

// TODO: check on the specific psql version 
int check_psql_installed(void) {
  raise_log("checking psql installed...");
  int returned = system("psql --version > /dev/null 2>&1");
  if (returned != 0) {
    raise_log("psql is not installed...");
    eprintf("psql is not installed or not in PATH.");
    return 1;
  }
  raise_log("psql is installed...");
  return 0;
}

/* Generate a migration name by choosing a random adjective and noun */
void generate_migration_name(char *buffer, size_t size) {
    const char *adjectives[] = {"quick", "lazy", "sleepy", "noisy", "hungry"};
    const char *nouns[] = {"fox", "dog", "cat", "mouse", "bear"};
    int num_adjectives = sizeof(adjectives) / sizeof(adjectives[0]);
    int num_nouns = sizeof(nouns) / sizeof(nouns[0]);
    int adj_index = rand() % num_adjectives;
    int noun_index = rand() % num_nouns;
    snprintf(buffer, size, "%s_%s", adjectives[adj_index], nouns[noun_index]);
}

/* Record that a migration has been applied
 * by inserting its filename into the database */
int record_migration(const char* db_url, const char* file_name) {
  char command[2048];
  snprintf(command, sizeof(command),
    "psql '%s' -c \"INSERT INTO hectic.migration (name) VALUES ('%s');\"",
      db_url, file_name);
  int returned = system(command);
  return returned;
}

void create_migration_inner(const char* migration_path, const char* type) {
  if (strcmp(type, "up") || strcmp(type, "down")) {
    raise_exception("migration type can only be up or down"); 
    exit(1);
  }

  char path[1024];
  snprintf(path, sizeof(path), "%s/%s", migration_path, type);
  
  /* create directory for current migration */
  if (mkdir(path, 0755) != 0 && errno != EEXIST) {
      eprintf("Error creating %s", path);
      exit(1);
  }

  char filename[1024];
  snprintf(filename, sizeof(filename), "%s/00-entry-point.sql", path);

  FILE *fp = fopen(filename, "w");
  if (!fp) {
      eprintf("Error creating %s", filename);
      exit(1);
  }
  fprintf(fp, "-- Write your migration SQL here\n");
  fclose(fp);
  printf("Created migration: %s\n", filename);

}

/* Create a migration in the given directory with the provided name.
 * The migration name is formed as "<timestamp>_<name>.sql". */
void create_migration(const char* migration_dir, const char* name) {
    /* Create the directory if it doesn't exist */
    if (mkdir(migration_dir, 0755) != 0 && errno != EEXIST) {
        eprintf("Error creating migration directory");
        exit(1);
    }

    /* create directory for current migration */
    time_t now = time(NULL);
    char path[1024];
    snprintf(path, sizeof(path), "%s/%ld-%s", migration_dir, now, name);
    
    if (mkdir(path, 0755) != 0 && errno != EEXIST) {
        eprintf("Error creating %s", path);
        exit(1);
    }

    create_migration_inner(path, "up");
    create_migration_inner(path, "down");
}

void help_message(char name[]) {
    fprintf(stdout, "Usage %s: TODO\n", name);
}

int main(int argc, char *argv[]) {
  srand(time(NULL));
  init_logger();

  raise_log("init");

  if (check_psql_installed()) { exit(1); }

  if (argc < 2) {
    help_message(argv[0]);
    exit(0);
  }

  int subcommand_index = 0;
  char *migration_dir;
  char *db_url;
  char *migration_name;

  /* Process global options until a known subcommand is encountered */
  int i = 1;
  for (; i < argc; i++) {
      if (strcmp(argv[i], "create") == 0 ||
          strcmp(argv[i], "migrate") == 0 ||
          strcmp(argv[i], "fetch") == 0) {
          subcommand_index = i;
          break;
      }
      if (strcmp(argv[i], "-d") == 0 || strcmp(argv[i], "--migration-dir") == 0) {
          if (i+1 < argc) {
              migration_dir = argv[i+1];
              i++;
          }
      }
  }

  if (subcommand_index == 0) {
    eprintf("No subcommand provided.\n");
    help_message(argv[0]);
    exit(1);
  }
    
  char *subcommand = argv[subcommand_index];

  if (strcmp(subcommand, "create") == 0) {
    for (i = subcommand_index+1; i < argc; i++) {
      if (strcmp(argv[i], "-n") == 0 || strcmp(argv[i], "--name") == 0) {
        if (i+1 < argc) {
          migration_name = argv[i+1];
          i++;
        }
      }
    }
    char generated_name[128];
    if (!migration_name) {
      generate_migration_name(generated_name, sizeof(generated_name));
      migration_name = generated_name;
    }
    create_migration(migration_dir, migration_name);
    return 0;
  }

  if (!db_url) {
    eprintf("Database URL is required for migrate subcommand.\n");
    help_message(argv[0]);
    exit(1);
  }


}
