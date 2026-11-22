//! Persists application state independently of configuration and host sessions.

use super::size::WindowSize;

use rusqlite::{Connection, OptionalExtension as _, TransactionBehavior, params};

use std::fmt;
use std::fs;
use std::io;
use std::path::Path;
use std::time::Duration;

const APPLICATION_ID: i64 = 0x4e41_5553;
const SCHEMA_VERSION: i64 = 2;

#[derive(Debug)]
pub(super) enum Error {
    Io(io::Error),
    Sqlite(rusqlite::Error),
    Invalid(&'static str),
    Version(i64),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(e) => e.fmt(f),
            Self::Sqlite(e) => e.fmt(f),
            Self::Invalid(reason) => f.write_str(reason),
            Self::Version(version) => {
                write!(f, "unsupported application state schema version {version}")
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

pub(super) struct History(Connection);

#[derive(Debug, PartialEq)]
pub(super) enum Destination {
    Local,
    Alias(String),
}

impl Destination {
    pub(super) fn into_alias(self) -> Option<String> {
        match self {
            Self::Local => None,
            Self::Alias(alias) => Some(alias),
        }
    }
}

impl History {
    pub(super) fn system() -> Result<Self, Error> {
        let root =
            dirs::data_local_dir().ok_or(Error::Invalid("platform data directory is absent"))?;
        Self::open(&root.join("nauvim/state.sqlite3"))
    }

    pub(super) fn open(path: &Path) -> Result<Self, Error> {
        if let Some(parent) = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            fs::create_dir_all(parent)?;
        }
        let mut conn = Connection::open(path)?;
        conn.busy_timeout(Duration::from_millis(25))?;

        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
        let application: i64 = tx.pragma_query_value(None, "application_id", |row| row.get(0))?;
        let version: i64 = tx.pragma_query_value(None, "user_version", |row| row.get(0))?;
        if application == 0 && version == 0 {
            let occupied: bool = tx.query_row(
                "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%')",
                [],
                |row| row.get(0),
            )?;
            if occupied {
                return Err(Error::Invalid("database belongs to another application"));
            }
            tx.execute_batch(
                "CREATE TABLE selection (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    alias TEXT CHECK (alias IS NULL OR (length(alias) > 0 AND instr(alias, char(0)) = 0))
                ) STRICT;",
            )?;
            tx.pragma_update(None, "application_id", APPLICATION_ID)?;
        } else {
            if application != APPLICATION_ID {
                return Err(Error::Invalid("database belongs to another application"));
            }
            if version != 1 && version != SCHEMA_VERSION {
                return Err(Error::Version(version));
            }
            tx.prepare("SELECT id, alias FROM selection LIMIT 0")?;
        }
        if version < SCHEMA_VERSION {
            tx.execute_batch(
                "CREATE TABLE window_size (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    width INTEGER NOT NULL CHECK (width BETWEEN 1 AND 4294967295),
                    height INTEGER NOT NULL CHECK (height BETWEEN 1 AND 4294967295)
                ) STRICT;",
            )?;
            tx.pragma_update(None, "user_version", SCHEMA_VERSION)?;
        } else {
            tx.prepare("SELECT id, width, height FROM window_size LIMIT 0")?;
        }
        tx.commit()?;
        Ok(Self(conn))
    }

    pub(super) fn load(&self) -> Result<Option<Destination>, Error> {
        let alias: Option<Option<String>> = self
            .0
            .query_row("SELECT alias FROM selection WHERE id = 1", [], |row| {
                row.get(0)
            })
            .optional()?;

        match alias {
            None => Ok(None),
            Some(None) => Ok(Some(Destination::Local)),
            Some(Some(alias)) if alias.is_empty() || alias.contains('\0') => Err(Error::Invalid(
                "stored host alias must be nonempty and contain no NUL",
            )),
            Some(Some(alias)) => Ok(Some(Destination::Alias(alias))),
        }
    }

    pub(super) fn save(&self, alias: Option<&str>) -> Result<(), Error> {
        let mut stmt = self.0.prepare_cached(
            "INSERT INTO selection (id, alias) VALUES (1, ?1)
             ON CONFLICT (id) DO UPDATE SET alias = excluded.alias",
        )?;
        stmt.execute([alias])?;
        Ok(())
    }

    pub(super) fn load_window_size(&self) -> Result<Option<WindowSize>, Error> {
        let size = self
            .0
            .query_row(
                "SELECT width, height FROM window_size WHERE id = 1",
                [],
                |row| Ok(WindowSize::new(row.get(0)?, row.get(1)?)),
            )
            .optional()?;

        match size {
            None => Ok(None),
            Some(Some(size)) => Ok(Some(size)),
            Some(None) => Err(Error::Invalid("stored window dimensions must be positive")),
        }
    }

    pub(super) fn save_window_size(&self, size: WindowSize) -> Result<(), Error> {
        self.0.execute(
            "INSERT INTO window_size (id, width, height) VALUES (1, ?1, ?2)
             ON CONFLICT (id) DO UPDATE SET width = excluded.width, height = excluded.height",
            params![size.width.get(), size.height.get()],
        )?;
        Ok(())
    }
}

#[cfg(test)]
mod tests;
