use std::process::Command;
use std::fs;
use std::path::Path;

#[test]
fn generated_sql_matches_expected() {
    // Adjust this path if your fixture folder is located somewhere else.
    let fixture_dir = "test/fixture";
    let input_db = format!("{}/test.db", fixture_dir);
    let expected_sql_path = format!("{}/expected.sql", fixture_dir);
    let output_sql_path = format!("{}/generated.sql", fixture_dir);

    // Remove any previously generated file.
    let _ = fs::remove_file(&output_sql_path);

    // Check that fixture files exist.
    assert!(
        Path::new(&input_db).exists(),
        "Input DB does not exist: {}",
        input_db
    );
    assert!(
        Path::new(&expected_sql_path).exists(),
        "Expected SQL does not exist: {}",
        expected_sql_path
    );

    // The following env var is set automatically by Cargo when building binaries.
    // It points to the location of the built binary (assuming your binary is named "pg-from").
    let exe = env!("CARGO_BIN_EXE_pg-from");

    // Run your binary with the required arguments.
    let status = Command::new(exe)
        .args(&[
            &input_db,
            &output_sql_path,
            "legacy",
            "--inherit=created_at",
            "--inherit=updated_at",
        ])
        .status()
        .expect("Failed to execute pg-from binary");

    assert!(
        status.success(),
        "pg-from did not run successfully (exit status: {:?})",
        status.code()
    );

    // Read the generated output and the expected output.
    let generated = fs::read_to_string(&output_sql_path)
        .expect("Failed to read generated SQL file");
    let expected = fs::read_to_string(&expected_sql_path)
        .expect("Failed to read expected SQL file");

    // Compare the two strings.
    assert_eq!(
        generated, expected,
        "Generated SQL does not match expected SQL"
    );
}

