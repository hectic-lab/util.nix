use postgres::Client;

pub fn init_db(client: &mut Client) {
    client.batch_execute("
        CREATE SCHEMA IF NOT EXISTS hectic;
        CREATE TABLE IF NOT EXISTS hectic.migration (
            id SERIAL PRIMARY KEY,
            name TEXT UNIQUE NOT NULL,
            applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
    ").unwrap();
}
