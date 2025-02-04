use rusqlite::{Connection, Result};
use rusqlite::types::ValueRef;
use std::collections::HashMap;
use std::env;
use std::error::Error;
use std::fs;
use std::fs::File;
use std::io::Write;
use tempfile::NamedTempFile;

/// Print help/usage information.
fn print_help(program: &str) {
    println!(
        "Usage: {} <sqlite_file> <output_sql_file> <postgres_schema> [--inherit=<inherit_clause> ...]\n\n\
         Options:\n  -h, --help              Show this help message\n  --inherit=<clause>      Specify a parent table to inherit (can be provided multiple times)\n\n\
         Example:\n  {} mydb.sqlite legacy_dump.sql legacy --inherit=\"created_at\" --inherit=\"updated_at\"",
        program, program
    );
}

/// Structure representing one column from PRAGMA table_info.
#[derive(Debug)]
struct ColumnInfo {
    #[allow(dead_code)]
    cid: i32,
    name: String,
    data_type: String,
    notnull: bool,
    dflt_value: Option<String>,
    pk: i32,
}

/// Converts an SQLite type to a PostgreSQL type (very simple logic).
fn convert_sqlite_type_to_postgres(sqlite_type: &str) -> String {
    let upper = sqlite_type.to_uppercase();
    if upper.contains("INT") {
        "bigint".to_string()
    } else if upper.contains("CHAR") || upper.contains("CLOB") || upper.contains("TEXT") {
        "text".to_string()
    } else if upper.contains("BLOB") {
        "bytea".to_string()
    } else if upper.contains("REAL") || upper.contains("FLOA") || upper.contains("DOUB") {
        "double precision".to_string()
    } else {
        "text".to_string()
    }
}

/// Generates the CREATE TABLE statement for a given table, based on PRAGMA table_info.
/// If an inheritance clause is provided, appends INHERITS (<clause>).
fn generate_create_table_sql(
    table: &str,
    conn: &Connection,
    schema: &str,
    inherit_clause: Option<&str>,
) -> Result<String, Box<dyn Error>> {
    let mut stmt = conn.prepare(&format!("PRAGMA table_info(\"{}\")", table))?;
    let columns: Vec<ColumnInfo> = stmt
        .query_map([], |row| {
            Ok(ColumnInfo {
                cid: row.get(0)?,
                name: row.get(1)?,
                data_type: row.get(2)?,
                notnull: row.get::<_, i32>(3)? != 0,
                dflt_value: row.get(4)?,
                pk: row.get(5)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    let mut column_defs = Vec::new();
    let pk_columns: Vec<&ColumnInfo> = columns.iter().filter(|col| col.pk > 0).collect();

    // If exactly one PK and its type starts with "INTEGER", generate SERIAL.
    let single_autoinc = if pk_columns.len() == 1 {
        let col = pk_columns[0];
        col.data_type.to_uppercase().starts_with("INTEGER")
    } else {
        false
    };

    for col in &columns {
        let mut col_def = format!("\"{}\" ", col.name);
        if single_autoinc && pk_columns[0].name == col.name {
            col_def.push_str("SERIAL PRIMARY KEY");
        } else {
            let pg_type = convert_sqlite_type_to_postgres(&col.data_type);
            col_def.push_str(&pg_type);
            if col.notnull {
                col_def.push_str(" NOT NULL");
            }
            if let Some(default) = &col.dflt_value {
                col_def.push_str(" DEFAULT ");
                col_def.push_str(default);
            }
            if pk_columns.len() == 1 && pk_columns[0].name == col.name {
                col_def.push_str(" PRIMARY KEY");
            }
        }
        column_defs.push(col_def);
    }

    // If composite primary key exists, add it as a separate constraint.
    if pk_columns.len() > 1 {
        let pk_names: Vec<String> = pk_columns
            .iter()
            .map(|col| format!("\"{}\"", col.name))
            .collect();
        let pk_def = format!("PRIMARY KEY ({})", pk_names.join(", "));
        column_defs.push(pk_def);
    }

    let mut table_sql = format!(
        "CREATE TABLE {}.\"{}\" (\n    {}\n)",
        schema,
        table,
        column_defs.join(",\n    ")
    );
    if let Some(inh) = inherit_clause {
        table_sql.push_str(&format!(" INHERITS ({})", inh));
    }
    table_sql.push(';');
    Ok(table_sql)
}

/// Generates DDL for indexes of a given table.
fn generate_indexes_sql(table: &str, conn: &Connection, schema: &str) -> Result<Vec<String>, Box<dyn Error>> {
    let mut indexes = Vec::new();
    let mut stmt = conn.prepare(&format!("PRAGMA index_list(\"{}\")", table))?;
    let index_list = stmt.query_map([], |row| {
        let name: String = row.get(1)?;
        let unique: i32 = row.get(2)?;
        Ok((name, unique))
    })?;
    for index_res in index_list {
        let (index_name, unique) = index_res?;
        if index_name.starts_with("sqlite_autoindex") {
            continue;
        }
        let mut stmt2 = conn.prepare(&format!("PRAGMA index_info(\"{}\")", index_name))?;
        let cols_iter = stmt2.query_map([], |row| {
            let col_name: String = row.get(2)?;
            Ok(col_name)
        })?;
        let mut cols = Vec::new();
        for col_res in cols_iter {
            cols.push(col_res?);
        }
        let unique_str = if unique != 0 { "UNIQUE " } else { "" };
        let index_sql = format!(
            "CREATE {}INDEX {} ON {}.\"{}\" ({});",
            unique_str,
            index_name,
            schema,
            table,
            cols.iter()
                .map(|c| format!("\"{}\"", c))
                .collect::<Vec<_>>()
                .join(", ")
        );
        indexes.push(index_sql);
    }
    Ok(indexes)
}

/// Represents one foreign key entry from PRAGMA foreign_key_list.
struct ForeignKeyInfo {
    id: i32,
    seq: i32,
    table: String,
    from: String,
    to: String,
    on_update: String,
    on_delete: String,
    #[allow(dead_code)]
    r#match: String,
}

/// Generates foreign key constraints for the given table. It groups rows by foreign key ID
/// (to support multi‑column foreign keys) and produces ALTER TABLE … ADD CONSTRAINT statements.
fn generate_foreign_keys_sql(
    table: &str,
    conn: &Connection,
    schema: &str,
) -> Result<Vec<String>, Box<dyn Error>> {
    let mut stmt = conn.prepare(&format!("PRAGMA foreign_key_list(\"{}\")", table))?;
    let fk_rows: Vec<ForeignKeyInfo> = stmt
        .query_map([], |row| {
            Ok(ForeignKeyInfo {
                id: row.get(0)?,
                seq: row.get(1)?,
                table: row.get(2)?,
                from: row.get(3)?,
                to: row.get(4)?,
                on_update: row.get(5)?,
                on_delete: row.get(6)?,
                r#match: row.get(7)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    // Group rows by foreign key ID.
    let mut fk_map: HashMap<i32, Vec<ForeignKeyInfo>> = HashMap::new();
    for fk in fk_rows {
        fk_map.entry(fk.id).or_default().push(fk);
    }
    let mut constraints = Vec::new();
    for (fk_id, mut fks) in fk_map {
        // Sort by sequence number.
        fks.sort_by_key(|fk| fk.seq);
        // All entries in this group refer to the same target table.
        let ref_table = &fks[0].table;
        let on_update = &fks[0].on_update;
        let on_delete = &fks[0].on_delete;
        let from_columns: Vec<String> = fks.iter().map(|fk| format!("\"{}\"", fk.from)).collect();
        let to_columns: Vec<String> = fks.iter().map(|fk| format!("\"{}\"", fk.to)).collect();
        // Generate a constraint name, e.g. fk_table_1.
        let constraint_name = format!("fk_{}_{}", table, fk_id);
        let mut constraint = format!(
            "ALTER TABLE {}.\"{}\" ADD CONSTRAINT {} FOREIGN KEY ({}) REFERENCES {}.\"{}\" ({})",
            schema,
            table,
            constraint_name,
            from_columns.join(", "),
            schema,
            ref_table,
            to_columns.join(", ")
        );
        if !on_update.is_empty() && on_update.to_uppercase() != "NO ACTION" {
            constraint.push_str(&format!(" ON UPDATE {}", on_update));
        }
        if !on_delete.is_empty() && on_delete.to_uppercase() != "NO ACTION" {
            constraint.push_str(&format!(" ON DELETE {}", on_delete));
        }
        constraint.push(';');
        constraints.push(constraint);
    }
    Ok(constraints)
}

/// Escapes a text value for the PostgreSQL COPY format (e.g. escapes backslashes).
fn escape_copy_text(s: &str) -> String {
    s.replace("\\", "\\\\")
}

/// Formats a single column value for the PostgreSQL COPY command. NULL values become "\N".
fn format_copy_field(value: ValueRef) -> String {
    match value {
        ValueRef::Null => "\\N".to_string(),
        ValueRef::Integer(i) => i.to_string(),
        ValueRef::Real(r) => r.to_string(),
        ValueRef::Text(t) => {
            let s = std::str::from_utf8(t).unwrap_or("");
            escape_copy_text(s)
        },
        ValueRef::Blob(b) => {
            // Convert blob to a hex string prefixed with \x.
            let hex: String = b.iter().map(|byte| format!("{:02X}", byte)).collect();
            format!("\\x{}", hex)
        },
    }
}

/// Dumps data for a table in PostgreSQL COPY format.
fn dump_table_data(table: &str, conn: &Connection, schema: &str, out: &mut File) -> Result<(), Box<dyn Error>> {
    // Get column names using PRAGMA table_info.
    let mut stmt = conn.prepare(&format!("PRAGMA table_info(\"{}\")", table))?;
    let column_names: Result<Vec<String>, _> = stmt.query_map([], |row| row.get(1))?.collect();
    let column_names = column_names?;
    
    // Write COPY header.
    writeln!(out, "\n-- Data for table {}", table)?;
    writeln!(out, "COPY {}.\"{}\" ({}) FROM stdin;", schema, table, column_names.join(", "))?;
    
    // Query all rows from the table.
    let mut stmt = conn.prepare(&format!("SELECT * FROM \"{}\"", table))?;
    let mut rows = stmt.query([])?;
    // Use the known number of columns.
    let col_count = column_names.len();
    while let Some(row) = rows.next()? {
        let mut fields = Vec::new();
        for i in 0..col_count {
            let value = row.get_ref(i)?;
            fields.push(format_copy_field(value));
        }
        // Write tab-separated fields.
        writeln!(out, "{}", fields.join("\t"))?;
    }
    // End COPY command.
    writeln!(out, "\\.")?;
    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    // Process command-line arguments.
    let args: Vec<String> = env::args().collect();
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        print_help(&args[0]);
        std::process::exit(0);
    }
    if args.len() < 4 {
        eprintln!("Error: Not enough arguments.\n");
        print_help(&args[0]);
        std::process::exit(1);
    }
    let sqlite_file = &args[1];
    let output_file = &args[2];
    let schema = &args[3];

    // Gather multiple --inherit options.
    let mut inherit_clauses: Vec<String> = Vec::new();
    for arg in &args[4..] {
        if arg.starts_with("--inherit=") {
            inherit_clauses.push(arg["--inherit=".len()..].to_string());
        }
    }
    let inherit_clause = if inherit_clauses.is_empty() {
        None
    } else {
        Some(inherit_clauses.join(", "))
    };

    // Copy the original SQLite file into a temporary file.
    let temp_file = NamedTempFile::new()?;
    fs::copy(sqlite_file, temp_file.path())?;
    let conn = Connection::open(temp_file.path())?;

    // Open (or create) the output file.
    let mut out = File::create(output_file)?;

    // Write header.
    writeln!(out, "-- PostgreSQL database dump generated from SQLite")?;
    writeln!(out, "CREATE SCHEMA IF NOT EXISTS {};\n", schema)?;
    writeln!(out, "SET client_encoding = 'UTF8';\n")?;

    // Get table names (excluding internal SQLite tables).
    let mut table_names = Vec::new();
    {
        let mut stmt = conn.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")?;
        let table_iter = stmt.query_map([], |row| row.get(0))?;
        for table_result in table_iter {
            let table: String = table_result?;
            table_names.push(table);
        }
    }

    // Generate DDL for each table, its indexes, and foreign key constraints.
    for table in &table_names {
        let table_sql = generate_create_table_sql(table, &conn, schema, inherit_clause.as_deref())?;
        writeln!(out, "{}\n", table_sql)?;
        writeln!(out, "ALTER TABLE {}.\"{}\" OWNER TO postgres;\n", schema, table)?;

        let indexes = generate_indexes_sql(table, &conn, schema)?;
        for idx in indexes {
            writeln!(out, "{}\n", idx)?;
        }
        let fkeys = generate_foreign_keys_sql(table, &conn, schema)?;
        for fk in fkeys {
            writeln!(out, "{}\n", fk)?;
        }
    }

    // Process sqlite_sequence (for autoincrement values).
    let sqlite_sequence_exists: bool = conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='sqlite_sequence')",
        [],
        |row| row.get(0)
    )?;
    if sqlite_sequence_exists {
        let mut stmt = conn.prepare("SELECT name, seq FROM sqlite_sequence")?;
        let seq_iter = stmt.query_map([], |row| {
            let table: String = row.get(0)?;
            let seq: i64 = row.get(1)?;
            Ok((table, seq))
        })?;
        for seq_result in seq_iter {
            let (table, seq) = seq_result?;
            let seq_name = format!("{}_{}_seq", schema, table);
            writeln!(
                out,
                "CREATE SEQUENCE {} START WITH {} INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;",
                seq_name,
                seq + 1
            )?;
        }
    }

    // Dump data for each table.
    for table in &table_names {
        dump_table_data(table, &conn, schema, &mut out)?;
    }

    Ok(())
}
