#include <stdio.h>
#include <stdlib.h>
#include "type.c"

LogLevel currentLogLevel = LOG_LEVEL_DEBUG;

// TODO: check on the specific psql version 
int check_psql_installed(void) {
  int returned = system("psql --version > /dev/null 2>&1");
  if (returned != 0) {
    fprintf(stderr, "Error: psql is not installed or not in PATH.\n");
    return 1;
  }
  return 0;
}

void help_message() {
    fprintf(stdout, "Usage: TODO");
}

int main(int argc, char *argv[]) {
  if (!check_psql_installed()) { exit(1); }

  if (argc < 2) {
    help_message();
  }
}
