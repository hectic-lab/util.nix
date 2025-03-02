use postgres::Config;

/// The macro usage:
/// 
/// config! {
///     db_url => "postgres://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}",
///     db_user,
///     db_password,
///     db_host,
///     db_port,
///     db_name,
///     individual_option,
///     another_bundle => "{option_1}@{option_2}",
///     option_1,
///     option_2
/// }
///
/// After expansion, you'll get a `Config` struct with fields:
/// - db_url (String)
/// - db_user (String)
/// - db_password (String)
/// - db_host (String)
/// - db_port (String)
/// - db_name (String)
/// - individual_option (String)
/// - another_bundle (String)
/// - option_1 (String)
/// - option_2 (String)
///
/// Logic:
/// - If `db_url` is provided (env or CLI), it sets `db_url` and ignores `db_user`, `db_password`, `db_host`, `db_port`, `db_name`.
/// - If `db_url` is not provided, tries to construct it from `db_user`, `db_password`, `db_host`, `db_port`, `db_name`.
///   If any is missing, error.
/// - Similarly for `another_bundle`.

macro_rules! config {
    (
        $($key:ident $(=> $template:expr)?),* $(,)?
    ) => {
        // Identify which keys are bundles (have a template) and which are single options
        struct Config {
            $(
                pub $key: String,
            )*
        }

        impl Config {
            pub fn from_env_and_args() -> Result<Self, String> {
                let args: Vec<String> = std::env::args().collect();

                fn get_arg(name: &str, args: &[String]) -> Option<String> {
                    let prefix = format!("--{}=", name);
                    args.iter()
                        .find(|a| a.starts_with(&prefix))
                        .map(|a| a[prefix.len()..].to_string())
                }

                fn get_env(name: &str) -> Option<String> {
                    std::env::var(name).ok()
                }

                // Helper to load a single option: first from args, then from env
                fn load_option(name: &str) -> Option<String> {
                    // command-line option name is the same as the field
                    // env var name is uppercase
                    get_arg(name, &args)
                        .or_else(|| get_env(&name.to_uppercase()))
                }

                // We'll store temporary values here
                let mut vals = std::collections::HashMap::new();
                $(
                    // Initialize all options to empty for now
                    vals.insert(stringify!($key), String::new());
                )*

                $(
                    // If this is a bundle
                    $(
                        if false {} else {
                            // This branch is for bundles
                            let bundle_name = stringify!($key);
                            let maybe_bundle = load_option(bundle_name);
                            if let Some(bundle_val) = maybe_bundle {
                                // If the bundle itself is provided, just set it and ignore its components
                                vals.insert(bundle_name, bundle_val);
                            } else {
                                // Bundle not provided. Need to construct from template.
                                let template_str = $template;

                                // Extract placeholders from the template
                                // placeholders are like {some_option}, we try to fill them
                                let mut constructed = template_str.to_string();
                                // Simple placeholder parsing
                                let mut placeholders = vec![];
                                {
                                    let mut start = 0usize;
                                    while let Some(open) = constructed[start..].find('{') {
                                        let open_idx = start + open;
                                        if let Some(close_idx) = constructed[open_idx..].find('}') {
                                            let close_idx = open_idx + close_idx;
                                            let placeholder = &constructed[(open_idx+1)..close_idx];
                                            placeholders.push(placeholder.to_string());
                                            start = close_idx+1;
                                        } else {
                                            break; // malformed, ignore for simplicity
                                        }
                                    }
                                }

                                // For each placeholder, we must load it from env/args
                                for ph in placeholders {
                                    let maybe_val = load_option(&ph);
                                    let val = maybe_val.ok_or_else(|| format!("Missing required option `{}` for bundle `{}`", ph, bundle_name))?;
                                    // Replace "{ph}" with val
                                    constructed = constructed.replace(&format!("{{{}}}", ph), &val);
                                    // Also store them individually if you want them accessible
                                    vals.insert(&ph, val);
                                }
                                vals.insert(bundle_name, constructed);
                            }
                        }
                    )?

                    // If this is a single option (not a bundle)
                    $( ; )? // do nothing if bundle line
                )*

                $(
                    // For single options (those without =>)
                    // If they haven't been set by a bundle line, set them now
                    $(
                        // This empty repetition is a trick
                    )?
                    $( 
                        // If no template was provided, this is a single option
                        if false {} else {
                            let name = stringify!($key);
                            // If a bundle line didn't already resolve it:
                            if !vals.contains_key(name) || vals[name].is_empty() {
                                if let Some(val) = load_option(name) {
                                    vals.insert(name, val);
                                } else {
                                    // If not provided and not part of a bundle that was resolved, default empty
                                    // or we can leave it empty silently
                                    vals.insert(name, "".to_string());
                                }
                            }
                        }
                    )?
                )*

                Ok(Config {
                    $(
                        $key: vals.remove(stringify!($key)).unwrap_or_default(),
                    )*
                })
            }
        }
    }
}

fn main() -> Result<(), String> {
    // Example usage
    config! {
        db_url => "postgres://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}",
        db_user,
        db_password,
        db_host,
        db_port,
        db_name,
        individual_option,
        another_bundle => "{option_1}@{option_2}",
        option_1,
        option_2
    }

    let cfg = Config::from_env_and_args()?;
    println!("db_url: {}", cfg.db_url);
    println!("individual_option: {}", cfg.individual_option);
    println!("another_bundle: {}", cfg.another_bundle);

    // ...
    Ok(())
}

