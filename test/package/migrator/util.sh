#!/bin/bash

# columns(table)
columns() {
  psql -Atc 'SELECT column_name
  FROM information_schema.columns
  WHERE table_name = '"${1};"
}
