use clap::{Arg, Command, ArgAction};
use postgres::{Client, NoTls};
use chrono::Utc;
use pg_migration_lib::init_db;
use std::{fs, path::Path, process::Command as ProcessCommand};
use rand::Rng;

fn main() {
    check_psql_installed();

    let matches = Command::new("Rust PG Migration Tool")
        .version("0.1")
        .arg(
            Arg::new("db_url")
                .short('u')
                .long("db-url")
                .env("PG_URL")
                .num_args(1)
                .required(true),
        )
        .arg(
            Arg::new("migration_dir")
                .short('d')
                .long("migration-dir")
                .env("MIGRATION_DIR")
                .num_args(1)
                .default_value("migration"),
        )
        .subcommand(
            Command::new("migrate").arg(
                Arg::new("force")
                    .short('f')
                    .long("force")
                    .action(ArgAction::SetTrue),
            ),
        )
        .subcommand(
            Command::new("create").arg(
                Arg::new("name")
                    .short('n')
                    .long("name")
                    .num_args(1),
            ),
        )
        .subcommand(Command::new("fetch"))
        .get_matches();

    let db_url = matches.get_one::<String>("db_url").unwrap();
    let migration_dir = matches.get_one::<String>("migration_dir").unwrap();
    let mut client = Client::connect(db_url, NoTls).expect("DB connection failed");
    init_db(&mut client);

    match matches.subcommand() {
        Some(("migrate", sub_m)) => {
            let force = sub_m.get_flag("force");
            apply_migrations(&mut client, migration_dir, db_url, force);
        }
        Some(("create", sub_m)) => {
            let name = sub_m
                .get_one::<String>("name")
                .cloned()
                .unwrap_or_else(generate_migration_name);
            create_migration_file(migration_dir, &name);
        }
        Some(("fetch", _)) => {
            fetch_migrations(&mut client, migration_dir);
        }
        _ => {}
    }
}

fn check_psql_installed() {
    if ProcessCommand::new("psql")
        .arg("--version")
        .output()
        .is_err()
    {
        eprintln!("Error: psql is not installed or not in PATH.");
        std::process::exit(1);
    }
}

fn apply_migrations(client: &mut Client, migration_dir: &str, db_url: &str, _force: bool) {
    let mut entries: Vec<_> = fs::read_dir(migration_dir)
        .expect("Reading migration directory failed")
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().and_then(|s| s.to_str()) == Some("sql"))
        .collect();
    entries.sort_by_key(|e| e.path());

    // (Migration tree validation omitted)

    for entry in entries {
        let file_path = entry.path();
        let file_name = file_path.file_name().unwrap().to_string_lossy();

        if client
            .query_opt("SELECT 1 FROM hectic.migration WHERE name = $1", &[&file_name])
            .expect("Query failed")
            .is_some()
        {
            continue;
        }

        let status = ProcessCommand::new("psql")
            .arg("-d")
            .arg(db_url)
            .arg("-f")
            .arg(file_path.to_str().unwrap())
            .status()
            .expect("psql execution failed");
        if !status.success() {
            eprintln!("Migration failed: {}", file_name);
            break;
        }
        client
            .execute("INSERT INTO hectic.migration (name) VALUES ($1)", &[&file_name])
            .expect("Recording migration failed");
    }
}

fn create_migration_file(migration_dir: &str, name: &str) {
    fs::create_dir_all(migration_dir).expect("Creating migration directory failed");
    let timestamp = Utc::now().timestamp();
    let file_name = format!("{}_{}.sql", timestamp, name);
    let file_path = Path::new(migration_dir).join(file_name);
    fs::write(&file_path, "-- Write your migration SQL here\n")
        .expect("Creating migration file failed");
    println!("Created migration: {:?}", file_path);
}

fn fetch_migrations(_client: &mut Client, _migration_dir: &str) {
    // (Fetch implementation omitted)
}

fn generate_migration_name() -> String {
    let adjectives = ["quick", "lazy", "sleepy", "noisy", "hungry"];
    let nouns = ["fox", "dog", "cat", "mouse", "bear"];
    let mut rng = rand::rng();
    let adj = adjectives[rng.random_range(0..adjectives.len())];
    let noun = nouns[rng.random_range(0..nouns.len())];
    format!("{}_{}", adj, noun)
}

