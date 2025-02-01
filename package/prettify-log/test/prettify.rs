use std::fs;
use std::process::Command;
use std::io::Write;
use tempfile::NamedTempFile;

#[test]
fn test_prettify() {
    let input_file = "test/fixture/test.log";
    let expected_output = fs::read_to_string("test/fixture/expected.log")
        .expect("Failed to read expected.log");

    let mut actual_output_file = NamedTempFile::new().expect("Failed to create temp file");

    let output = Command::new("cargo")
        .args(&["run", "--quiet"])
        .stdin(fs::File::open(input_file).expect("Failed to open test.log"))
        .output()
        .expect("Failed to run prettify_logs");

    assert!(output.status.success());

    actual_output_file
        .write_all(&output.stdout)
        .expect("Failed to write output");

    let actual_output = String::from_utf8_lossy(&output.stdout);

    assert_eq!(actual_output.trim(), expected_output.trim(), "Output does not match expected.log");

    if actual_output.trim() != expected_output.trim() {
        eprintln!(
            "Test failed! Actual output saved to: {}",
            actual_output_file.path().display()
        );
    }
}

#[test]
fn test_prettify_colored() {
    let input_file = "test/fixture/test.log";
    let expected_output = fs::read_to_string("test/fixture/expected-colored.log")
        .expect("Failed to read expected.log");

    let mut actual_output_file = NamedTempFile::new().expect("Failed to create temp file");

    let output = Command::new("cargo")
        .args(&["run", "--quiet", "--", "--color-output"])
        .stdin(fs::File::open(input_file).expect("Failed to open test.log"))
        .output()
        .expect("Failed to run prettify_logs");

    assert!(output.status.success());

    actual_output_file
        .write_all(&output.stdout)
        .expect("Failed to write output");

    let actual_output = String::from_utf8_lossy(&output.stdout);

    assert_eq!(actual_output.trim(), expected_output.trim(), "Output does not match expected.log");

    if actual_output.trim() != expected_output.trim() {
        eprintln!(
            "Test failed! Actual output saved to: {}",
            actual_output_file.path().display()
        );
    }
}
