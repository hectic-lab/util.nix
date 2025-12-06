#!/bin/bash

# columns(table)
columns() {
  psql -Atc 'SELECT column_name
  FROM information_schema.columns
  WHERE table_name = '"${1};"
}

# is_number(var)
is_number() {
  case "$1" in
    *[!0-9]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}
