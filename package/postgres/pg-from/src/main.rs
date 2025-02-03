use rusqlite::{Connection, Result};
use std::env;
use std::error::Error;
use std::fs::File;
use std::io::Write;

/// Вывод справки по использованию утилиты.
fn print_help(program: &str) {
    println!(
        "Usage: {} <sqlite_file> <output_sql_file> <postgres_schema> [--inherit=<inherit_clause>]\n\n\
         Options:\n  -h, --help              Show this help message\n  --inherit=<clause>      Specify parent table(s) to inherit (e.g. \"created_at, updated_at\")\n\n\
         Example:\n  {} mydb.sqlite legacy_dump.sql legacy --inherit=\"created_at, updated_at\"",
        program, program
    );
}

/// Структура для хранения информации о столбце (результат PRAGMA table_info).
#[derive(Debug)]
struct ColumnInfo {
    cid: i32,
    name: String,
    data_type: String,
    notnull: bool,
    dflt_value: Option<String>,
    pk: i32,
}

/// Преобразует строку типа из SQLite в тип PostgreSQL.
/// Здесь применяется простая логика: если тип содержит "INT" – выдаётся bigint,
/// если содержит "CHAR", "TEXT" или "CLOB" – text, если "REAL", "FLOA" или "DOUB" – double precision, и т.д.
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

/// Генерирует DDL для создания таблицы в PostgreSQL на основе информации из PRAGMA table_info.
/// Если задан параметр наследования (inherit_clause), то после списка столбцов добавляется
/// конструкция INHERITS (<inherit_clause>).
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

    // Собираем список столбцов и определяем первичные ключи.
    let mut column_defs = Vec::new();
    let pk_columns: Vec<&ColumnInfo> = columns.iter().filter(|col| col.pk > 0).collect();

    // Если имеется ровно один первичный ключ и его тип начинается с "INTEGER",
    // то для него генерируем тип SERIAL (PostgreSQL автоматически создаст sequence).
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

    // Если составной ключ, добавляем ограничение отдельно.
    if pk_columns.len() > 1 {
        let pk_names: Vec<String> = pk_columns
            .iter()
            .map(|col| format!("\"{}\"", col.name))
            .collect();
        let pk_def = format!("PRIMARY KEY ({})", pk_names.join(", "));
        column_defs.push(pk_def);
    }

    // Собираем итоговую инструкцию.
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

/// Генерирует DDL для индексов таблицы.
/// Используются PRAGMA index_list и PRAGMA index_info для извлечения информации об индексах.
/// Автоиндексы (имена начинаются с "sqlite_autoindex") пропускаются.
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

fn main() -> Result<(), Box<dyn Error>> {
    // Обработка аргументов командной строки.
    let args: Vec<String> = env::args().collect();
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        print_help(&args[0]);
        std::process::exit(0);
    }
    if args.len() < 4 {
        eprintln!("Error: Недостаточно аргументов.\n");
        print_help(&args[0]);
        std::process::exit(1);
    }
    let sqlite_file = &args[1];
    let output_file = &args[2];
    let schema = &args[3];

    // Если передана опция наследования, извлекаем её значение.
    let mut inherit_clause: Option<String> = None;
    for arg in &args[4..] {
        if arg.starts_with("--inherit=") {
            inherit_clause = Some(arg["--inherit=".len()..].to_string());
        }
    }

    // Открываем SQLite БД.
    let conn = Connection::open(sqlite_file)?;

    // Открываем (или создаём) выходной файл.
    let mut out = File::create(output_file)?;

    // Записываем заголовок.
    writeln!(out, "-- PostgreSQL database dump generated from SQLite")?;
    writeln!(out, "CREATE SCHEMA IF NOT EXISTS {};\n", schema)?;
    writeln!(out, "SET client_encoding = 'UTF8';\n")?;

    // Получаем имена таблиц (исключая внутренние).
    let mut stmt = conn.prepare(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    )?;
    let table_names = stmt.query_map([], |row| row.get(0))?;
    for table_name_result in table_names {
        let table_name: String = table_name_result?;
        // Генерируем DDL для таблицы, передавая также опциональный inherit_clause.
        let table_sql = generate_create_table_sql(&table_name, &conn, schema, inherit_clause.as_deref())?;
        writeln!(out, "{}\n", table_sql)?;
        writeln!(out, "ALTER TABLE {}.\"{}\" OWNER TO postgres;\n", schema, table_name)?;

        // Генерируем DDL для индексов.
        let indexes = generate_indexes_sql(&table_name, &conn, schema)?;
        for idx in indexes {
            writeln!(out, "{}\n", idx)?;
        }
    }

    // Обработка таблицы sqlite_sequence (для автоинкрементных значений).
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

    Ok(())
}
