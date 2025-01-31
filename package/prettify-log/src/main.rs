use std::io::{self, BufRead};
use serde_json::Value;

/// Finds the substring from the first '{' to its matching '}', handling nested braces.
fn find_json_block(line: &str) -> Option<(usize, usize)> {
    let start = line.find('{')?;
    let mut brace_count = 0;
    for (i, ch) in line[start..].char_indices() {
        if ch == '{' {
            brace_count += 1;
        } else if ch == '}' {
            brace_count -= 1;
            if brace_count == 0 {
                // Return the byte-range of the entire JSON block
                return Some((start, start + i + 1));
            }
        }
    }
    None
}

fn main() -> io::Result<()> {
    let stdin = io::stdin();

    for line_result in stdin.lock().lines() {
        let line = line_result?;
        if let Some((start, end)) = find_json_block(&line) {
            let candidate = &line[start..end];
            if let Ok(json) = serde_json::from_str::<Value>(candidate) {
                let pretty = serde_json::to_string_pretty(&json).unwrap();
                let prefix = &line[..start];
                let suffix = &line[end..];
                println!("{}{}{}", prefix, pretty, suffix);
                continue;
            }
        }
        // If no valid JSON found, print as-is
        println!("{}", line);
    }

    Ok(())
}
