if ! migration_table_sql="$(migrator --inherits tablename --inherits 'table name' --init-dry-run)"; then
  log error "test failed: error on migration table init dry run"
fi

printf '%s' "$migration_table_sql" | grep -Eq 'INHERITS[[:space:]]*\([[:space:]]*"tablename"[[:space:]]*,[[:space:]]*"table name"[[:space:]]*\)' ||
  { log error "not correct migration table inherits"; exit 1; }
