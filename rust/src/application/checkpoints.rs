use nauvim_core::{Checkpoint, CheckpointError};
use nvim_rpc_ui::Limits;
use rusqlite::types::ValueRef;
use rusqlite::{Connection, OpenFlags, TransactionBehavior, params};

use std::fmt;
use std::fs;
use std::io::{self, ErrorKind};
use std::os::unix::fs::{OpenOptionsExt as _, PermissionsExt as _};
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

const FILE_NAME: &str = "ui-checkpoints.sqlite3";
const APPLICATION_ID: i64 = 0x4e41_5543;
const SCHEMA_VERSION: i64 = 1;
const MAX_CHECKPOINT_BYTES: usize = 64 * 1024 * 1024;
const MAX_DATABASE_BYTES: i64 = 512 * 1024 * 1024;
const MAX_ENTRIES: i64 = 64;

#[derive(Debug)]
pub(super) enum Error {
    Io(io::Error),
    Sqlite(rusqlite::Error),
    Checkpoint(CheckpointError),
    Invalid(&'static str),
    Version(i64),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(e) => e.fmt(f),
            Self::Sqlite(e) => e.fmt(f),
            Self::Checkpoint(e) => e.fmt(f),
            Self::Invalid(reason) => f.write_str(reason),
            Self::Version(version) => {
                write!(
                    f,
                    "unsupported UI checkpoint database schema version {version}"
                )
            }
        }
    }
}

impl From<io::Error> for Error {
    fn from(e: io::Error) -> Self {
        Self::Io(e)
    }
}

impl From<rusqlite::Error> for Error {
    fn from(e: rusqlite::Error) -> Self {
        Self::Sqlite(e)
    }
}

impl From<CheckpointError> for Error {
    fn from(e: CheckpointError) -> Self {
        Self::Checkpoint(e)
    }
}

#[derive(Clone)]
pub(super) struct Checkpoints(Arc<Path>);

impl Checkpoints {
    pub(super) fn system() -> Result<Self, Error> {
        let root =
            dirs::data_local_dir().ok_or(Error::Invalid("platform data directory is absent"))?;
        Ok(Self(root.join("nauvim").join(FILE_NAME).into()))
    }

    pub(super) fn beside(path: &Path) -> Self {
        Self(path.with_file_name(FILE_NAME).into())
    }

    pub(super) fn load(&self, token: &str) -> Result<Option<Checkpoint>, Error> {
        let mut db = match self.connect() {
            Ok(db) => db,
            Err(Error::Io(e)) if e.kind() == ErrorKind::NotFound => return Ok(None),
            Err(e) => return Err(e),
        };
        let tx = db.transaction()?;
        if !initialized(&tx)? {
            return Ok(None);
        }

        let mut stmt = tx.prepare(
            "SELECT CASE WHEN length(checkpoint) <= ?2 THEN checkpoint END
             FROM ui_checkpoints WHERE token = ?1",
        )?;
        let mut rows = stmt.query((token, MAX_CHECKPOINT_BYTES as i64))?;
        let Some(row) = rows.next()? else {
            return Ok(None);
        };
        let ValueRef::Blob(bytes) = row.get_ref(0)? else {
            return Err(checkpoint_size_error());
        };

        let checkpoint = Checkpoint::decode(bytes, Limits::default(), MAX_CHECKPOINT_BYTES)?;
        Ok(Some(checkpoint))
    }

    pub(super) fn save(&self, token: &str, checkpoint: &Checkpoint) -> Result<(), Error> {
        let bytes = checkpoint.encode()?;
        if bytes.len() > MAX_CHECKPOINT_BYTES {
            return Err(checkpoint_size_error());
        }

        if let Some(parent) = self.0.parent().filter(|path| !path.as_os_str().is_empty()) {
            fs::create_dir_all(parent)?;
        }
        // The contents include editor text. SQLite also uses the database mode
        // for its journal, so create the file before opening it through SQLite.
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&self.0)
        {
            Ok(_) => (),
            Err(e) if e.kind() == ErrorKind::AlreadyExists => (),
            Err(e) => return Err(e.into()),
        }

        let mut db = self.connect()?;
        limit_pages(&db)?;
        let tx = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
        if !initialized(&tx)? {
            let occupied: bool = tx.query_row(
                "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%')",
                [],
                |row| row.get(0),
            )?;
            if occupied {
                return Err(Error::Invalid("database belongs to another application"));
            }
            tx.execute_batch(
                "CREATE TABLE ui_checkpoints (
                    id INTEGER PRIMARY KEY,
                    token TEXT NOT NULL UNIQUE,
                    checkpoint BLOB NOT NULL
                ) STRICT;",
            )?;
            tx.pragma_update(None, "application_id", APPLICATION_ID)?;
            tx.pragma_update(None, "user_version", SCHEMA_VERSION)?;
        }

        tx.execute(
            "INSERT OR REPLACE INTO ui_checkpoints (token, checkpoint) VALUES (?1, ?2)",
            params![token, bytes],
        )?;
        tx.execute(
            "DELETE FROM ui_checkpoints WHERE id IN (
                SELECT id FROM ui_checkpoints ORDER BY id DESC LIMIT -1 OFFSET ?1
            )",
            [MAX_ENTRIES],
        )?;
        tx.commit()?;
        Ok(())
    }

    fn connect(&self) -> Result<Connection, Error> {
        let metadata = fs::symlink_metadata(&self.0)?;
        if !metadata.is_file() || metadata.permissions().mode() & 0o077 != 0 {
            return Err(Error::Invalid(
                "UI checkpoint database requires a private regular file",
            ));
        }
        let db = Connection::open_with_flags(
            self.0.canonicalize()?,
            OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_NOFOLLOW,
        )?;
        db.busy_timeout(Duration::from_millis(25))?;
        Ok(db)
    }
}

fn checkpoint_size_error() -> Error {
    Error::Checkpoint(CheckpointError::Limit("stored bytes"))
}

fn initialized(db: &Connection) -> Result<bool, Error> {
    let app: i64 = db.pragma_query_value(None, "application_id", |row| row.get(0))?;
    let version: i64 = db.pragma_query_value(None, "user_version", |row| row.get(0))?;
    match (app, version) {
        (0, 0) => Ok(false),
        (APPLICATION_ID, SCHEMA_VERSION) => Ok(true),
        (APPLICATION_ID, version) => Err(Error::Version(version)),
        _ => Err(Error::Invalid("database belongs to another application")),
    }
}

fn limit_pages(db: &Connection) -> Result<(), Error> {
    let size: i64 = db.pragma_query_value(None, "page_size", |row| row.get(0))?;
    let pages = MAX_DATABASE_BYTES
        .checked_div(size)
        .filter(|pages| *pages > 0)
        .ok_or(Error::Invalid("invalid UI checkpoint database page size"))?;
    let actual: i64 =
        db.pragma_update_and_check(None, "max_page_count", pages, |row| row.get(0))?;
    if actual > pages {
        return Err(Error::Invalid(
            "UI checkpoint database exceeds the storage limit",
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    use nvim_rpc_ui::{ConnectionOptions, NoHandler, connect};
    use tempfile::tempdir;
    use tokio::io::{AsyncWriteExt as _, duplex, split};
    use tokio::time::timeout;

    async fn checkpoint(title: &[u8; 5]) -> Checkpoint {
        let (mut host, client) = duplex(256);
        let (rdr, wtr) = split(client);
        let mut conn = connect(rdr, wtr, NoHandler, ConnectionOptions::default()).unwrap();

        // An RPC notification with redraw events for set_title and flush.
        let mut redraw = b"\x93\x02\xa6redraw\x92\x92\xa9set_title\x91\xa5".to_vec();
        redraw.extend_from_slice(title);
        redraw.extend_from_slice(b"\x92\xa5flush\x90");
        host.write_all(&redraw).await.unwrap();
        let frame = timeout(Duration::from_secs(2), conn.frames.recv())
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        assert_eq!(frame.state.title.as_bytes(), title);
        let checkpoint = conn.frames.checkpoint().unwrap();
        conn.close_and_wait().await.unwrap();
        checkpoint
    }

    #[tokio::test]
    async fn restores_latest_private_checkpoint_per_session() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("state.sqlite3");
        let store = Checkpoints::beside(&path);
        assert!(store.load("first session").unwrap().is_none());
        assert!(!store.0.exists());

        let first = checkpoint(b"first").await;
        let later = checkpoint(b"later").await;
        store.save("first session", &first).unwrap();
        store.save("second session", &first).unwrap();
        store.save("first session", &later).unwrap();
        drop(store);

        let store = Checkpoints::beside(&path);
        for (token, title) in [("first session", "later"), ("second session", "first")] {
            let saved = store.load(token).unwrap().unwrap();
            assert_eq!(saved.state().title.as_ref(), title);
        }
        assert!(store.load("unknown session").unwrap().is_none());
        let permissions = fs::metadata(&store.0).unwrap().permissions();
        assert_eq!(permissions.mode() & 0o077, 0);
        assert!(!path.exists());
    }

    #[tokio::test]
    async fn rejects_invalid_checkpoint_data_and_schema() {
        let dir = tempdir().unwrap();
        let store = Checkpoints::beside(&dir.path().join("state.sqlite3"));
        let checkpoint = checkpoint(b"first").await;
        store.save("session", &checkpoint).unwrap();

        let db = store.connect().unwrap();
        db.execute("UPDATE ui_checkpoints SET checkpoint = X'62726f6b656e'", [])
            .unwrap();
        assert!(matches!(
            store.load("session"),
            Err(Error::Checkpoint(CheckpointError::Invalid("header")))
        ));

        store.save("session", &checkpoint).unwrap();
        db.pragma_update(None, "user_version", 2).unwrap();
        assert!(matches!(store.load("session"), Err(Error::Version(2))));
        assert!(matches!(
            store.save("session", &checkpoint),
            Err(Error::Version(2))
        ));
    }

    #[tokio::test]
    async fn prunes_oldest_sessions_after_refresh() {
        let dir = tempdir().unwrap();
        let store = Checkpoints::beside(&dir.path().join("state.sqlite3"));
        let checkpoint = checkpoint(b"first").await;

        for index in 0..MAX_ENTRIES {
            let token = format!("session-{index}");
            store.save(&token, &checkpoint).unwrap();
        }
        store.save("session-0", &checkpoint).unwrap();
        store.save("new session", &checkpoint).unwrap();

        assert!(store.load("session-0").unwrap().is_some());
        assert!(store.load("session-1").unwrap().is_none());
        assert!(store.load("new session").unwrap().is_some());
    }
}
