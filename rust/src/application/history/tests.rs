use super::*;

#[test]
fn restores_named_manual_and_default_destinations_after_reopening() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("state.sqlite3");
    assert_eq!(History::open(&path).unwrap().load().unwrap(), None);

    for alias in [
        Some("local"),
        None,
        Some("Local"),
        Some("work.example.com"),
        Some("作業"),
        None,
    ] {
        let history = History::open(&path).unwrap();
        history.save(alias).unwrap();
        drop(history);

        let history = History::open(&path).unwrap();
        assert_eq!(
            history.load().unwrap(),
            Some(DisplayDestination {
                alias: alias.map(str::to_owned)
            }),
        );
        let rows: i64 = history
            .0
            .query_row("SELECT count(*) FROM selection", [], |row| row.get(0))
            .unwrap();
        assert_eq!(rows, 1);
    }
}

#[test]
fn preserves_unknown_and_damaged_databases() {
    for (application, version) in [(123, 1), (APPLICATION_ID, 2), (0, 0), (APPLICATION_ID, 1)] {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("state.sqlite3");
        let conn = Connection::open(&path).unwrap();
        conn.execute_batch("CREATE TABLE saved (value TEXT); INSERT INTO saved VALUES ('keep')")
            .unwrap();
        conn.pragma_update(None, "application_id", application)
            .unwrap();
        conn.pragma_update(None, "user_version", version).unwrap();
        drop(conn);

        let before = fs::read(&path).unwrap();
        assert!(History::open(&path).is_err(), "{application}, {version}");
        assert_eq!(fs::read(&path).unwrap(), before);
    }

    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("state.sqlite3");
    fs::write(&path, b"damaged SQLite database").unwrap();
    assert!(History::open(&path).is_err());
    assert_eq!(fs::read(&path).unwrap(), b"damaged SQLite database");
}

#[test]
fn reports_locked_storage_and_retains_the_previous_selection() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("state.sqlite3");
    let history = History::open(&path).unwrap();
    history.save(Some("local")).unwrap();
    let mut conn = Connection::open(&path).unwrap();
    let tx = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .unwrap();
    assert!(history.save(None).is_err());
    drop(tx);
    assert_eq!(
        history.load().unwrap().unwrap().alias.as_deref(),
        Some("local")
    );
}

#[test]
fn persists_without_process_cleanup() {
    use std::env;
    use std::process::{self, Command};

    if let Some(path) = env::var_os("NAUVIM_TEST_HOST_HISTORY") {
        let history = History::open(Path::new(&path)).unwrap();
        let alias = env::var("NAUVIM_TEST_HOST_ALIAS").ok();
        history.save(alias.as_deref()).unwrap();

        // Exit while SQLite is still open, without running Drop or shutdown.
        process::exit(0);
    }

    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("state.sqlite3");
    for alias in [
        Some("local"),
        None,
        Some("Local"),
        Some("manual-host"),
        None,
    ] {
        let mut command = Command::new(env::current_exe().unwrap());
        command
            .args([
                "--exact",
                "application::history::tests::persists_without_process_cleanup",
                "--nocapture",
            ])
            .env("NAUVIM_TEST_HOST_HISTORY", &path);
        if let Some(alias) = alias {
            command.env("NAUVIM_TEST_HOST_ALIAS", alias);
        } else {
            command.env_remove("NAUVIM_TEST_HOST_ALIAS");
        }
        let output = command.output().unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(
            History::open(&path).unwrap().load().unwrap(),
            Some(DisplayDestination {
                alias: alias.map(str::to_owned)
            }),
        );
    }
}
