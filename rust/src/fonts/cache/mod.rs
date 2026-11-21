//! Stores rebuildable prepared faces without owning font discovery or selection.

use crate::api::fonts::{FontInfo, FontVariation, ResolvedFont};

mod payload;
use payload::{Encoded, checksum};

use rusqlite::types::ValueRef;
use rusqlite::{Connection, OptionalExtension as _, Row, TransactionBehavior};
use sha2::{Digest as _, Sha256};

use std::env::consts::{ARCH, OS};
use std::fmt;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::Duration;

const APPLICATION_ID: i64 = 0x4e41_5546;
const SCHEMA_VERSION: i64 = 1;
const MAX_BYTES: usize = 67_108_864;
const MAX_ENTRIES: i64 = 128;

#[derive(Debug)]
pub(super) struct Error {
    path: Option<PathBuf>,
    source: Failure,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if let Some(path) = &self.path {
            write!(f, "{}: ", path.display())?;
        }
        self.source.fmt(f)
    }
}

#[derive(Debug)]
enum Failure {
    Io(io::Error),
    Sqlite(rusqlite::Error),
    Invalid(&'static str),
    Version(i64),
}

impl fmt::Display for Failure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(e) => e.fmt(f),
            Self::Sqlite(e) => e.fmt(f),
            Self::Invalid(reason) => f.write_str(reason),
            Self::Version(version) => write!(f, "unsupported font cache schema version {version}"),
        }
    }
}

impl From<io::Error> for Failure {
    fn from(e: io::Error) -> Self {
        Self::Io(e)
    }
}

impl From<rusqlite::Error> for Failure {
    fn from(e: rusqlite::Error) -> Self {
        Self::Sqlite(e)
    }
}

pub(super) struct Key([u8; 32]);

impl Key {
    pub(super) fn new(source: &[u8], index: u32) -> Self {
        let mut hash = Sha256::new();
        // Bump this domain whenever selection/export or the metrics policy changes.
        hash.update(b"nauvim-prepared-font-v1\0");
        hash.update(OS.as_bytes());
        hash.update([0]);
        hash.update(ARCH.as_bytes());
        hash.update([0]);
        hash.update(index.to_le_bytes());
        hash.update(source);
        Self(hash.finalize().into())
    }
}

pub(super) struct Cache {
    conn: Connection,
    path: PathBuf,
}

pub(super) struct CachedFace {
    // Standalone files can reuse the identical source buffer. Extracted faces
    // must carry their own bytes because the source remains a collection.
    replacement: Option<Vec<u8>>,
    info: FontInfo,
    variations: Vec<FontVariation>,
}

impl CachedFace {
    pub(super) fn into_font(self, request: u32, source: Vec<u8>) -> ResolvedFont {
        ResolvedFont {
            request,
            data: self.replacement.unwrap_or(source),
            info: self.info,
            variations: self.variations,
        }
    }
}

impl Cache {
    pub(super) fn system() -> Result<Self, Error> {
        let mut path = dirs::cache_dir().ok_or(Error {
            path: None,
            source: Failure::Invalid("platform cache directory is absent"),
        })?;
        path.push("nauvim/fonts.sqlite3");
        Self::open(path)
    }

    pub(super) fn open(path: PathBuf) -> Result<Self, Error> {
        match Self::open_connection(&path) {
            Ok(conn) => Ok(Self { conn, path }),
            Err(source) => Err(Error {
                path: Some(path),
                source,
            }),
        }
    }

    fn open_connection(path: &Path) -> Result<Connection, Failure> {
        if let Some(parent) = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            fs::create_dir_all(parent)?;
        }
        let mut conn = Connection::open(path)?;
        conn.busy_timeout(Duration::from_millis(25))?;

        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
        let version: i64 = tx.pragma_query_value(None, "user_version", |row| row.get(0))?;
        let application: i64 = tx.pragma_query_value(None, "application_id", |row| row.get(0))?;
        if version == 0 && application == 0 {
            let occupied: bool = tx.query_row(
                "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%')",
                [],
                |row| row.get(0),
            )?;
            if occupied {
                return Err(Failure::Invalid("database belongs to another application"));
            }
            tx.execute_batch(
                "CREATE TABLE fonts (
                    key BLOB PRIMARY KEY,
                    data BLOB NOT NULL,
                    metrics BLOB NOT NULL,
                    coverage BLOB NOT NULL,
                    variations BLOB NOT NULL,
                    checksum BLOB NOT NULL,
                    used INTEGER NOT NULL
                ) STRICT, WITHOUT ROWID;",
            )?;
            tx.pragma_update(None, "application_id", APPLICATION_ID)?;
            tx.pragma_update(None, "user_version", SCHEMA_VERSION)?;
        } else {
            if application != APPLICATION_ID {
                return Err(Failure::Invalid("database belongs to another application"));
            }
            if version != SCHEMA_VERSION {
                return Err(Failure::Version(version));
            }
            tx.prepare("SELECT key, data, metrics, coverage, variations, checksum, used FROM fonts LIMIT 0")?;
        }
        tx.commit()?;

        Ok(conn)
    }

    pub(super) fn get(&self, key: &Key, source: &[u8]) -> Result<Option<CachedFace>, Error> {
        self.get_inner(key, source).map_err(|source| Error {
            path: Some(self.path.clone()),
            source,
        })
    }

    fn get_inner(&self, key: &Key, source: &[u8]) -> Result<Option<CachedFace>, Failure> {
        let key = [key.0.as_slice()];
        let stored = self
            .conn
            .prepare_cached(
                "SELECT data, metrics, coverage, variations, checksum FROM fonts WHERE key = ?1",
            )?
            .query_row(key, |row| read_font(row, source))
            .optional()?;
        match stored {
            None => Ok(None),
            Some(None) => {
                self.conn
                    .prepare_cached("DELETE FROM fonts WHERE key = ?1")?
                    .execute(key)?;
                Ok(None)
            }
            Some(Some(font)) => {
                self.conn
                    .prepare_cached(
                        "UPDATE fonts SET used = (SELECT coalesce(max(used), 0) + 1 FROM fonts)
                         WHERE key = ?1",
                    )?
                    .execute(key)?;
                Ok(Some(font))
            }
        }
    }

    pub(super) fn put(&mut self, key: &Key, font: &ResolvedFont) -> Result<(), Error> {
        self.put_inner(key, font).map_err(|source| Error {
            path: Some(self.path.clone()),
            source,
        })
    }

    fn put_inner(&mut self, key: &Key, font: &ResolvedFont) -> Result<(), Failure> {
        let Some(encoded) = Encoded::new(font) else {
            return Ok(());
        };
        let columns @ [data, metrics, coverage, variations] = encoded.columns();
        let checksum = checksum(&columns);
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        tx.prepare_cached(
            "INSERT INTO fonts (key, data, metrics, coverage, variations, checksum, used)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, (SELECT coalesce(max(used), 0) + 1 FROM fonts))
             ON CONFLICT(key) DO UPDATE SET data = excluded.data, metrics = excluded.metrics,
                 coverage = excluded.coverage, variations = excluded.variations,
                 checksum = excluded.checksum, used = excluded.used",
        )?
        .execute((
            key.0.as_slice(),
            data,
            metrics,
            coverage,
            variations,
            checksum.as_slice(),
        ))?;
        tx.prepare_cached(
            "DELETE FROM fonts WHERE key IN (
                 SELECT key FROM (
                     SELECT key,
                         row_number() OVER (ORDER BY used DESC, key) AS rank,
                         sum(length(data) + length(metrics) + length(coverage) + length(variations))
                             OVER (ORDER BY used DESC, key) AS bytes
                     FROM fonts
                 ) WHERE rank > ?1 OR bytes > ?2
             )",
        )?
        .execute((MAX_ENTRIES, MAX_BYTES))?;
        tx.commit()?;
        Ok(())
    }
}

fn read_font(row: &Row<'_>, source: &[u8]) -> rusqlite::Result<Option<CachedFace>> {
    let (
        ValueRef::Blob(data),
        ValueRef::Blob(metrics),
        ValueRef::Blob(coverage),
        ValueRef::Blob(variations),
        ValueRef::Blob(checksum),
    ) = (
        row.get_ref(0)?,
        row.get_ref(1)?,
        row.get_ref(2)?,
        row.get_ref(3)?,
        row.get_ref(4)?,
    )
    else {
        return Ok(None);
    };
    Ok(CachedFace::decode(
        [data, metrics, coverage, variations],
        checksum,
        source,
    ))
}

#[cfg(test)]
mod tests;
