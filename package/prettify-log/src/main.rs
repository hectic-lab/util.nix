use std::io::{self, BufRead};
use std::env;
use serde_json::Value;
use colored_json::{ColorMode, ToColoredJson};
use regex::Regex;

/// Finds the first '{' and tries to match nested braces until the corresponding '}'.
fn find_json_block(line: &str) -> Option<(usize, usize)> {
    let start = line.find('{')?;
    let mut brace_count = 0;
    for (i, ch) in line[start..].char_indices() {
        match ch {
            '{' => brace_count += 1,
            '}' => {
                brace_count -= 1;
                if brace_count == 0 {
                    return Some((start, start + i + 1));
                }
            }
            _ => {}
        }
    }
    None
}

/// Applies color to known log keywords (e.g. ERROR, DEBUG) without coloring the colon.
/// Captures the preceding boundary, the keyword, and the colon, then colors only the keyword.
fn colorize_keywords(line: &str) -> String {
    let red = "\x1b[31m";
    let blue = "\x1b[34m";
    let green = "\x1b[32m";
    let yellow = "\x1b[33m";
    let magenta = "\x1b[35m";
    let cyan = "\x1b[36m";
    let reset = "\x1b[0m";

    let patterns = vec![
        (Regex::new(r"(?i)(^|[^A-Za-z])(ERROR)(:)").unwrap(), format!("$1{red}$2{reset}$3", red=red, reset=reset)),
        (Regex::new(r"(?i)(^|[^A-Za-z])(DEBUG)(:)").unwrap(), format!("$1{blue}$2{reset}$3", blue=blue, reset=reset)),
        (Regex::new(r"(?i)(^|[^A-Za-z])(INFO)(:)").unwrap(), format!("$1{green}$2{reset}$3", green=green, reset=reset)),
        (Regex::new(r"(?i)(^|[^A-Za-z])(LOG)(:)").unwrap(), format!("$1{green}$2{reset}$3", green=green, reset=reset)),
        (Regex::new(r"(?i)(^|[^A-Za-z])(EXCEPTION)(:)").unwrap(), format!("$1{magenta}$2{reset}$3", magenta=magenta, reset=reset)),
        (Regex::new(r"(?i)(^|[^A-Za-z])(WARNING)(:)").unwrap(), format!("$1{yellow}$2{reset}$3", yellow=yellow, reset=reset)),
        (Regex::new(r"(?i)(^|[^A-Za-z])(NOTICE)(:)").unwrap(), format!("$1{cyan}$2{reset}$3", cyan=cyan, reset=reset)),
        (Regex::new(r"(?i)(^|[^A-Za-z])(HINT)(:)").unwrap(), format!("$1{cyan}$2{reset}$3", cyan=cyan, reset=reset)),
        (Regex::new(r"(?i)(^|[^A-Za-z])(FATAL)(:)").unwrap(), format!("$1{magenta}$2{reset}$3", magenta=magenta, reset=reset)),
        (Regex::new(r"(?i)(^|[^A-Za-z])(DETAIL)(:)").unwrap(), format!("$1{cyan}$2{reset}$3", cyan=cyan, reset=reset)),
        (Regex::new(r"(?i)(^|[^A-Za-z])(STATEMENT)(:)").unwrap(), format!("$1{cyan}$2{reset}$3", cyan=cyan, reset=reset)),
    ];

    let mut out = String::from(line);
    for (re, replacement) in patterns {
        // Replace all occurrences
        out = re.replace_all(&out, replacement.as_str()).to_string();
    }
    out
}

fn conditionally_colorize_keywords<'a>(line: &'a str, force_color: bool) -> String {
        if force_color {
            colorize_keywords(&line)
        } else if atty::is(atty::Stream::Stdout) {
            colorize_keywords(&line)
        } else {
            line.to_string()
        }
}

fn main() -> io::Result<()> {
    let mut force_color = false;
    for arg in env::args().skip(1) {
        if arg == "--color-output" {
            force_color = true;
        }
    }

    let stdin = io::stdin();
    for line_result in stdin.lock().lines() {
        let line = line_result?;
        if let Some((start, end)) = find_json_block(&line) {
            let candidate = &line[start..end];
            if let Ok(json) = serde_json::from_str::<Value>(candidate) {
                let pretty = serde_json::to_string_pretty(&json).unwrap();

                let colorized = if force_color {
                    pretty.to_colored_json(ColorMode::On).unwrap()
                } else {
                    pretty.to_colored_json_auto().unwrap()
                };

                let prefix = conditionally_colorize_keywords(&line[..start], force_color);
                let suffix = conditionally_colorize_keywords(&line[end..], force_color);
                println!("{}{}{}", prefix, colorized, suffix);
                continue;
            }
        }

        // If no valid JSON found or parsing fails, print unchanged
        println!("{}", conditionally_colorize_keywords(&line, force_color));
    }
    Ok(())
}
