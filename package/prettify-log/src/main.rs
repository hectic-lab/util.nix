use std::io::{self, BufRead};
use std::env;
use serde_json::Value;
use colored_json::{ColorMode, ToColoredJson};
use regex::{Regex, Captures};
use once_cell::sync::Lazy;

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

static RE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)(^|[^A-Za-z])(?P<kw>ERROR|DEBUG|INFO|LOG|EXCEPTION|WARNING|NOTICE|HINT|FATAL|DETAIL|STATEMENT)(:)").unwrap()
});

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

    RE.replace_all(line, |caps: &Captures| {
        let prefix = caps.get(1).unwrap().as_str();
        let keyword = caps.name("kw").unwrap().as_str();
        let suffix = caps.get(3).unwrap().as_str();
        let key = match keyword.to_lowercase().as_str() {
            "error"     => format!("{}{}{}{}", prefix, red, keyword, reset),
            "debug"     => format!("{}{}{}{}", prefix, blue, keyword, reset),
            "info" | "log"
                        => format!("{}{}{}{}", prefix, green, keyword, reset),
            "exception" | "fatal"
                        => format!("{}{}{}{}", prefix, magenta, keyword, reset),
            "warning"   => format!("{}{}{}{}", prefix, yellow, keyword, reset),
            "notice" | "hint" | "detail" | "statement"
                        => format!("{}{}{}{}", prefix, cyan, keyword, reset),
            _           => caps[0].to_string(),
        }; 
        key + suffix
    }).to_string()
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
