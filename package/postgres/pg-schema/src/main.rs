use dotenv::dotenv;
use postgres::{Client, NoTls};
use regex::Regex;
use std::collections::{HashMap, HashSet};
use std::env;
use std::process::Command;
use log::info;

#[derive(Debug)]
struct Column {
    name: String,
    data_type: String,
    is_nullable: bool,
}

#[derive(Debug)]
struct ForeignKeyGroup {
    constraint_name: String,
    source_schema: String,
    source_table: String,
    target_schema: String,
    target_table: String,
    source_columns: Vec<String>,
    target_columns: Vec<String>,
    is_unique: bool,
}

// --- Sanitization functions ---

fn sanitize_type(data_type: &str) -> String {
    let re = Regex::new(r"\s+").unwrap();
    re.replace_all(&data_type.to_lowercase(), "_")
        .to_uppercase()
        .to_string()
}

fn sanitize_name(name: &str) -> String {
    // Replace spaces and hyphens with underscores and remove invalid characters
    let re = Regex::new(r"[\s\-]+").unwrap();
    let name = re.replace_all(name, "_");
    let re = Regex::new(r"[^\w_]").unwrap();
    re.replace_all(&name, "").to_string()
}

// --- Database Schema queries ---

fn get_tables(client: &mut Client) -> Result<Vec<(String, String)>, postgres::Error> {
    let rows = client.query(
        "
        SELECT table_schema, table_name
        FROM information_schema.tables
        WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'cron')
          AND table_schema NOT LIKE 'pg_toast%'
          AND table_type = 'BASE TABLE'
        ORDER BY table_schema, table_name;
        ",
        &[],
    )?;
    info!("{rows:#?}");
    Ok(rows
        .iter()
        .map(|row| (row.get::<_, String>(0), row.get::<_, String>(1)))
        .collect())
}

fn get_columns(
    client: &mut Client,
    schema: &str,
    table: &str,
) -> Result<Vec<Column>, postgres::Error> {
    let rows = client.query(
        "
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'cron')
          AND table_schema NOT LIKE 'pg_toast%'
          AND table_schema = $1
          AND table_name = $2
        ORDER BY ordinal_position;
        ",
        &[&schema, &table],
    )?;
    let mut columns = Vec::new();
    for row in rows {
        let col_name: String = row.get(0);
        let data_type: String = row.get(1);
        let is_nullable_str: String = row.get(2);
        let is_nullable = is_nullable_str.to_lowercase() == "yes";
        let sanitized_col_name = sanitize_name(&col_name.to_lowercase());
        let sanitized_type = sanitize_type(&data_type);
        columns.push(Column {
            name: sanitized_col_name,
            data_type: sanitized_type,
            is_nullable,
        });
    }
    Ok(columns)
}

// Improved foreign key query that gathers constraint_name and uniqueness info,
// so that composite foreign keys are grouped together.
fn get_foreign_keys(client: &mut Client) -> Result<Vec<ForeignKeyGroup>, postgres::Error> {
    let query = "
    SELECT
      tc.constraint_name,
      tc.table_schema AS source_schema,
      tc.table_name AS source_table,
      kcu.column_name AS source_column,
      ccu.table_schema AS target_schema,
      ccu.table_name AS target_table,
      ccu.column_name AS target_column,
      (
        EXISTS (
          SELECT 1
          FROM information_schema.table_constraints as utc
          JOIN information_schema.key_column_usage as ukcu
            ON utc.constraint_name = ukcu.constraint_name
          WHERE utc.table_schema = tc.table_schema
            AND utc.table_name = tc.table_name
            AND utc.constraint_type IN ('PRIMARY KEY', 'UNIQUE')
            AND ukcu.column_name = kcu.column_name
        )
      ) as is_unique
    FROM information_schema.table_constraints AS tc
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage AS ccu
      ON tc.constraint_name = ccu.constraint_name
    WHERE
      tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema NOT IN ('pg_catalog', 'information_schema', 'cron')
      AND tc.table_schema NOT LIKE 'pg_toast%'
    ORDER BY tc.constraint_name, kcu.ordinal_position;
    ";
    let rows = client.query(query, &[])?;
    let mut map: HashMap<String, ForeignKeyGroup> = HashMap::new();
    for row in rows {
        let constraint_name: String = row.get("constraint_name");
        let source_schema: String = row.get("source_schema");
        let source_table: String = row.get("source_table");
        let target_schema: String = row.get("target_schema");
        let target_table: String = row.get("target_table");
        let source_column: String = row.get("source_column");
        let target_column: String = row.get("target_column");
        let is_unique: bool = row.get("is_unique");

        let entry = map.entry(constraint_name.clone()).or_insert(ForeignKeyGroup {
            constraint_name: constraint_name.clone(),
            source_schema: source_schema.clone(),
            source_table: source_table.clone(),
            target_schema: target_schema.clone(),
            target_table: target_table.clone(),
            source_columns: Vec::new(),
            target_columns: Vec::new(),
            is_unique: true,
        });
        entry.source_columns.push(source_column);
        entry.target_columns.push(target_column);
        entry.is_unique = entry.is_unique && is_unique;
    }
    Ok(map.into_iter().map(|(_, v)| v).collect())
}

// --- Utility for generating diagram ---

fn get_hash(text: &str) -> String {
    use sha2::{Sha256, Digest};
    let mut hasher = Sha256::new();
    hasher.update(text.as_bytes());
    let result = hasher.finalize();
    format!("_{}", hex::encode(result))
}

/// Generates the Mermaid diagram.
/// - `tables`: all non-join tables (after join tables are removed)
/// - `foreign_keys`: grouped foreign key relationships
/// - `join_tables`: a vector of join table keys with their foreign key groups
/// - `join_table_keys`: set of join table identifiers to filter out regular relationships
fn generate_mermaid(
    tables: &HashMap<(String, String), Vec<Column>>,
    foreign_keys: &[ForeignKeyGroup],
    join_tables: &Vec<((String, String), Vec<&ForeignKeyGroup>)>,
    join_table_keys: &HashSet<(String, String)>
) -> String {
    let mut mermaid = String::from("erDiagram\n");

    // Define entities for non-join tables
    for ((schema, table), columns) in tables {
        let sanitized_schema = sanitize_name(schema);
        let sanitized_table = sanitize_name(table);
        let full_name = format!("{}.{}", sanitized_schema, sanitized_table);
        mermaid.push_str(&format!("    {}[\"{}\"] {{\n", get_hash(&full_name), full_name));
        for column in columns {
            mermaid.push_str(&format!("        {} {}\n", column.data_type, sanitize_name(&column.name)));
        }
        mermaid.push_str("    }\n");
    }
    mermaid.push_str("\n");

    // Normal relationships (one-to-one or one-to-many)
    for fk in foreign_keys {
        // Skip relationships that originate from join tables (handled separately)
        if join_table_keys.contains(&(fk.source_schema.clone(), fk.source_table.clone())) {
            continue;
        }
        let sanitized_source_table = sanitize_name(&fk.source_table);
        let sanitized_target_table = sanitize_name(&fk.target_table);
        let sanitized_source_schema = sanitize_name(&fk.source_schema);
        let sanitized_target_schema = sanitize_name(&fk.target_schema);
        let source_full_name = format!("{}.{}", sanitized_source_schema, sanitized_source_table);
        let target_full_name = format!("{}.{}", sanitized_target_schema, sanitized_target_table);
        let relationship_label = format!("{} -> {}", fk.source_columns.join(", "), fk.target_columns.join(", "));
        let relationship_type = if fk.is_unique { "||--||" } else { "}o--||" };
        mermaid.push_str(&format!(
            "    {} {} {} : \"{}\"\n",
            get_hash(&source_full_name),
            relationship_type,
            get_hash(&target_full_name),
            relationship_label
        ));
    }

    // Many-to-many relationships for detected join tables
    for (join_key, fk_list) in join_tables {
        if fk_list.len() == 2 {
            let fk1 = fk_list[0];
            let fk2 = fk_list[1];
            // Draw an edge between the two target tables of the join table.
            let source_full_name = format!("{}.{}", sanitize_name(&fk1.target_schema), sanitize_name(&fk1.target_table));
            let target_full_name = format!("{}.{}", sanitize_name(&fk2.target_schema), sanitize_name(&fk2.target_table));
            let label = format!("join: {} <-> {}", fk1.target_columns.join(", "), fk2.target_columns.join(", "));
            mermaid.push_str(&format!(
                "    {} }}|--|{{ {} : \"{}\"\n",
                get_hash(&source_full_name),
                get_hash(&target_full_name),
                label
            ));
        }
    }

    mermaid
}

fn generate_svg(mermaid_file: &str, svg_file: &str) -> Result<(), String> {
    let mmdc_path = which::which("mmdc").map_err(|_| {
        "Mermaid CLI (mmdc) is not installed or not found in PATH.\nPlease install it by running: npm install -g @mermaid-js/mermaid-cli".to_string()
    })?;
    let status = Command::new(mmdc_path)
        .arg("-i")
        .arg(mermaid_file)
        .arg("-o")
        .arg(svg_file)
        .status()
        .map_err(|e| format!("Failed to execute mmdc: {}", e))?;
    if status.success() {
        println!("SVG diagram generated successfully as '{}'.", svg_file);
        Ok(())
    } else {
        Err("An error occurred while generating the SVG.".to_string())
    }
}

fn main() {
    dotenv().ok();
    env_logger::init();

    // If DB_URL is provided, use it. Otherwise, fall back to individual parameters.
    let conn_str = match env::var("DB_URL") {
        Ok(url) => {
            info!("Using DB_URL environment variable for connection.");
            url
        },
        Err(_) => {
            let db_host = env::var("DB_HOST").unwrap_or_else(|_| {
                eprintln!("No DB_HOST environment variable provided.");
                std::process::exit(1);
            });
            info!("DB_HOST: {:?}", db_host);

            let db_port = env::var("DB_PORT").unwrap_or_else(|_| {
                eprintln!("No DB_PORT environment variable provided.");
                std::process::exit(1);
            });
            let db_name = env::var("DB_NAME").unwrap_or_else(|_| {
                eprintln!("No DB_NAME environment variable provided.");
                std::process::exit(1);
            });
            let db_user = env::var("DB_USER").unwrap_or_else(|_| {
                eprintln!("No DB_USER environment variable provided.");
                std::process::exit(1);
            });
            let db_password = env::var("DB_PASSWORD").unwrap_or_else(|_| {
                eprintln!("No DB_PASSWORD environment variable provided.");
                std::process::exit(1);
            });
            format!("host={} port={} dbname={} user={} password={}", db_host, db_port, db_name, db_user, db_password)
        }
    };

    let mut client = match Client::connect(&conn_str, NoTls) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Unable to connect to the database:\n{}", e);
            std::process::exit(1);
        }
    };

    // Fetch tables and columns
    let tables_list = match get_tables(&mut client) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("Error fetching tables:\n{}", e);
            std::process::exit(1);
        }
    };

    let mut tables: HashMap<(String, String), Vec<Column>> = HashMap::new();
    for (schema, table) in &tables_list {
        match get_columns(&mut client, schema, table) {
            Ok(cols) => {
                tables.insert((schema.clone(), table.clone()), cols);
            }
            Err(e) => {
                eprintln!("Error fetching columns for table '{}':\n{}", table, e);
                std::process::exit(1);
            }
        }
    }

    // Fetch grouped foreign keys (composite keys handled together)
    let foreign_keys = match get_foreign_keys(&mut client) {
        Ok(fks) => fks,
        Err(e) => {
            eprintln!("Error fetching foreign keys:\n{}", e);
            std::process::exit(1);
        }
    };

    // --- Detect join tables for many-to-many relationships ---
    // Build a map from (schema, table) to foreign key groups where the table is the source.
    let mut fk_by_source: HashMap<(String, String), Vec<&ForeignKeyGroup>> = HashMap::new();
    for fk in &foreign_keys {
        fk_by_source
            .entry((fk.source_schema.clone(), fk.source_table.clone()))
            .or_default()
            .push(fk);
    }

    // A join table is defined as having exactly two columns and exactly two foreign keys.
    let mut join_table_keys_vec: Vec<(String, String)> = Vec::new();
    for ((schema, table), columns) in &tables {
        if let Some(fk_list) = fk_by_source.get(&(schema.clone(), table.clone())) {
            if columns.len() == fk_list.len() && fk_list.len() == 2 {
                join_table_keys_vec.push((schema.clone(), table.clone()));
            }
        }
    }
    let join_table_keys: HashSet<(String, String)> = join_table_keys_vec.iter().cloned().collect();

    // Build a vector with join table key and its foreign key groups.
    let mut join_tables: Vec<((String, String), Vec<&ForeignKeyGroup>)> = Vec::new();
    for key in join_table_keys_vec {
        if let Some(fk_list) = fk_by_source.get(&key) {
            join_tables.push((key, fk_list.clone()));
        }
    }
    // Remove join tables from the main entities so they aren’t drawn separately.
    for key in &join_table_keys {
        tables.remove(key);
    }

    // Generate the Mermaid diagram
    let mermaid_diagram = generate_mermaid(&tables, &foreign_keys, &join_tables, &join_table_keys);

    // For now, we simply print the diagram (or you could write it to a file)
    println!("{mermaid_diagram}");

    client.close().expect("Failed to close the database connection.");
}
