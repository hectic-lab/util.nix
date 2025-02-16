use postgres::Client;

pub fn init_db(client: &mut Client, inherits: &[String]) {
    let inherits_clause = if !inherits.is_empty() {
        format!(" INHERITS ({})", inherits.join(", "))
    } else {
        String::new()
    };

    client .batch_execute(&format!("
CREATE SCHEMA IF NOT EXISTS hectic;
CREATE TABLE IF NOT EXISTS hectic.migration (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
){}
    ", inherits_clause)).unwrap();
}
