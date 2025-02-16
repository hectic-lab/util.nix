use clap::{Arg, Command, ArgAction};
use postgres::{Client, NoTls};
use chrono::Utc;
use pg_migration_lib::init_db;
use std::{fs, path::Path, process::{self, Command as ProcessCommand}};
use rand::Rng;

fn main() {
    if let Err(code) = run_app() {
        process::exit(code);
    }
}

fn run_app() -> Result<(), i32> {
    check_psql_installed();

    let matches = Command::new("Rust PG Migration Tool")
        .version("0.1")
        .arg(
            Arg::new("migration_dir")
                .short('d')
                .long("migration-dir")
                .env("MIGRATION_DIR")
                .num_args(1)
                .default_value("migration"),
        )
        .arg(
            Arg::new("inherits")
                .long("inherits")
                .num_args(1..)
                .help("List one or more tables the migration table must inherit from"),
        )
        .subcommand(
            Command::new("migrate").arg(
                Arg::new("force")
                    .short('f')
                    .long("force")
                    .action(ArgAction::SetTrue),
            )
            .arg(
                Arg::new("db_url")
                    .short('u')
                    .long("db-url")
                    .env("PG_URL")
                    .required(true)
                    .num_args(1),
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
        .subcommand(
            Command::new("fetch").arg(
                Arg::new("db_url")
                    .short('u')
                    .long("db-url")
                    .env("PG_URL")
                    .required(true)
                    .num_args(1),
            ),
        )
        .get_matches();
    
    let migration_dir = matches.get_one::<String>("migration_dir").unwrap();
    let inherits: Vec<String> = matches
      .get_many::<String>("inherits")
      .map(|vals| vals.cloned().collect())
      .unwrap_or_else(Vec::new);

    match matches.subcommand() {
        Some(("create", sub_m)) => {
            let name = sub_m
                .get_one::<String>("name")
                .cloned()
                .unwrap_or_else(generate_migration_name);
            create_migration_file(migration_dir, &name);
            Ok(())
        }
        Some(("migrate", sub_m)) => {
            let db_url = matches.get_one::<String>("db_url").unwrap();
            let mut client = Client::connect(db_url, NoTls).expect("DB connection failed");
            init_db(&mut client, &inherits);
            let force = sub_m.get_flag("force");
            apply_migrations(&mut client, migration_dir, db_url, force)
        }
        Some(("fetch", _)) => {
            let db_url = matches.get_one::<String>("db_url").unwrap();
            let mut client = Client::connect(db_url, NoTls).expect("DB connection failed");
            init_db(&mut client, &inherits);
            fetch_migrations(&mut client, migration_dir);
            Ok(())
        }
        _ => Ok(()),
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

fn apply_migrations(client: &mut Client, migration_dir: &str, db_url: &str, force: bool) -> Result<(), i32> {
    // Get the list of new migrations from disk
    let mut fs_entries: Vec<_> = fs::read_dir(migration_dir)
        .expect("Reading migration directory failed")
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().and_then(|s| s.to_str()) == Some("sql"))
        .collect();
    fs_entries.sort_by_key(|e| e.path());
    let fs_migrations: Vec<String> = fs_entries
        .iter()
        .map(|e| e.path().file_name().unwrap().to_string_lossy().into_owned())
        .collect();

    // Get the list of already applied migrations from DB
    let rows = client
        .query("SELECT name FROM hectic.migration ORDER BY name ASC", &[])
        .expect("Query failed");
    let db_migrations: Vec<String> = rows.iter().map(|row| row.get(0)).collect();

    // Check if the DB migrations form a proper prefix of disk migrations
    // (meaning all DB-applied migration filenames should appear in the same order at the start).
    for (i, db_mig) in db_migrations.iter().enumerate() {
        if i >= fs_migrations.len() || fs_migrations[i] != *db_mig {
            // The DB has migrations that are not found in the same position on disk -> unrelated tree
            if !force {
                eprintln!("Unrelated migration tree detected. Use --force to proceed.");
                return Err(2);
            } else {
                eprintln!("Unrelated migration tree forced. Proceeding...");
                break;
            }
        }
    }

    for fs_mig in fs_migrations {
        // Skip if already applied
        if db_migrations.contains(&fs_mig) {
            continue;
        }

        let status = std::process::Command::new("psql")
            .arg("-d")
            .arg(db_url)
            .arg("-f")
            .arg(Path::new(migration_dir).join(&fs_mig).to_str().unwrap())
            .status()
            .expect("psql execution failed");

        if !status.success() {
            eprintln!("Migration failed: {}", fs_mig);
            return Err(3);
        }

        client
            .execute("INSERT INTO hectic.migration (name) VALUES ($1)", &[&fs_mig])
            .expect("Recording migration failed");
    }

    Ok(())
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
