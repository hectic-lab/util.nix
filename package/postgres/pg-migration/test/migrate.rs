// #[cfg(test)]
// mod tests {
//     use postgres::{Client, NoTls};
//     use pg_migration_lib::init_db;
//     use testcontainers::{
//         core::{IntoContainerPort, WaitFor},
//         GenericImage, ImageExt,
//         runners::AsyncRunner
//     };
// 
//     #[test]
//     async fn test_init_db() {
//         let container = GenericImage::new("postgres", "latest")
//             .with_exposed_port(5432.tcp())
//             .with_wait_for(WaitFor::message_on_stdout("database system is ready"))
//             .with_env_var("POSTGRES_PASSWORD", "postgres")
//             .start().await
//             .expect("Failed to start container");
// 
//         let host_port = container.get_host_port(5432).expect("No mapped port");
//         let db_url = format!(
//             "postgres://postgres:postgres@127.0.0.1:{}/postgres",
//             host_port
//         );
// 
//         let mut client = Client::connect(&db_url, NoTls).expect("DB connection failed");
//         init_db(&mut client);
// 
//         let row = client
//             .query_one(
//                 "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'hectic'",
//                 &[],
//             )
//             .unwrap();
//         assert_eq!(row.get::<_, &str>(0), "hectic");
//     }
// }
 
