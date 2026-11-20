//! Stores rebuildable prepared faces without owning font discovery or selection.

use crate::api::fonts::{FontInfo, FontRange, FontVariation, ResolvedFont};

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

impl Cache {
    pub(super) fn system() -> Result<Self, Error> {
        let root = dirs::cache_dir().ok_or(Error {
            path: None,
            source: Failure::Invalid("platform cache directory is absent"),
        })?;
        Self::open(&root.join("nauvim/fonts.sqlite3"))
    }

    pub(super) fn open(path: &Path) -> Result<Self, Error> {
        Self::open_inner(path).map_err(|source| Error {
            path: Some(path.to_path_buf()),
            source,
        })
    }

    fn open_inner(path: &Path) -> Result<Self, Failure> {
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

        Ok(Self {
            conn,
            path: path.to_path_buf(),
        })
    }

    pub(super) fn get(&mut self, key: &Key, request: u32) -> Result<Option<ResolvedFont>, Error> {
        self.get_inner(key, request).map_err(|source| Error {
            path: Some(self.path.clone()),
            source,
        })
    }

    fn get_inner(&mut self, key: &Key, request: u32) -> Result<Option<ResolvedFont>, Failure> {
        let stored = self
            .conn
            .query_row(
                "SELECT data, metrics, coverage, variations, checksum FROM fonts WHERE key = ?1",
                [key.0.as_slice()],
                |row| Ok(Stored::read(row)?.and_then(|stored| stored.decode(request))),
            )
            .optional()?;
        let Some(stored) = stored else {
            return Ok(None);
        };
        let Some(font) = stored else {
            self.conn
                .execute("DELETE FROM fonts WHERE key = ?1", [key.0.as_slice()])?;
            return Ok(None);
        };
        self.conn.execute(
            "UPDATE fonts SET used = (SELECT coalesce(max(used), 0) + 1 FROM fonts) WHERE key = ?1",
            [key.0.as_slice()],
        )?;
        Ok(Some(font))
    }

    pub(super) fn put(&mut self, key: &Key, font: &ResolvedFont) -> Result<(), Error> {
        self.put_inner(key, font).map_err(|source| Error {
            path: Some(self.path.clone()),
            source,
        })
    }

    fn put_inner(&mut self, key: &Key, font: &ResolvedFont) -> Result<(), Failure> {
        if font.data.len() > MAX_BYTES {
            return Ok(());
        }
        let metrics = [
            font.info.ascent.to_le_bytes(),
            font.info.descent.to_le_bytes(),
            font.info.line_gap.to_le_bytes(),
            font.info.advance.to_le_bytes(),
        ];
        let metrics = metrics.as_flattened();
        let mut coverage = Vec::new();
        for range in &font.info.coverage {
            coverage.extend(range.first.to_le_bytes());
            coverage.extend(range.last.to_le_bytes());
        }
        let mut variations = Vec::new();
        for axis in &font.variations {
            variations.extend(axis.axis.as_bytes());
            variations.extend(axis.value.to_le_bytes());
        }
        let columns = [font.data.as_slice(), metrics, &coverage, &variations];
        if payload_size(&columns).is_none_or(|size| size > MAX_BYTES) {
            return Ok(());
        }
        let checksum = checksum(&columns);
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        tx.execute(
            "INSERT INTO fonts (key, data, metrics, coverage, variations, checksum, used)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, (SELECT coalesce(max(used), 0) + 1 FROM fonts))
             ON CONFLICT(key) DO UPDATE SET data = excluded.data, metrics = excluded.metrics,
                 coverage = excluded.coverage, variations = excluded.variations,
                 checksum = excluded.checksum, used = excluded.used",
            (
                key.0.as_slice(),
                font.data.as_slice(),
                metrics,
                &coverage,
                &variations,
                checksum.as_slice(),
            ),
        )?;
        tx.execute(
            "DELETE FROM fonts WHERE key IN (
                 SELECT key FROM (
                     SELECT key,
                         row_number() OVER (ORDER BY used DESC, key) AS rank,
                         sum(length(data) + length(metrics) + length(coverage) + length(variations))
                             OVER (ORDER BY used DESC, key) AS bytes
                     FROM fonts
                 ) WHERE rank > ?1 OR bytes > ?2
             )",
            (MAX_ENTRIES, MAX_BYTES),
        )?;
        tx.commit()?;
        Ok(())
    }
}

struct Stored<'a> {
    data: &'a [u8],
    metrics: &'a [u8],
    coverage: &'a [u8],
    variations: &'a [u8],
    checksum: &'a [u8],
}

impl<'a> Stored<'a> {
    fn read(row: &'a Row<'_>) -> rusqlite::Result<Option<Self>> {
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
        if payload_size(&[data, metrics, coverage, variations]).is_none_or(|size| size > MAX_BYTES)
            || checksum.len() != 32
        {
            return Ok(None);
        }
        Ok(Some(Self {
            data,
            metrics,
            coverage,
            variations,
            checksum,
        }))
    }

    fn decode(self, request: u32) -> Option<ResolvedFont> {
        if checksum(&[self.data, self.metrics, self.coverage, self.variations]).as_slice()
            != self.checksum
        {
            return None;
        }
        let mut metrics = self.metrics;
        let ascent = number(&mut metrics)?;
        let descent = number(&mut metrics)?;
        let line_gap = number(&mut metrics)?;
        let advance = number(&mut metrics)?;
        let height = ascent + descent;
        if !metrics.is_empty()
            || ascent < 0.0
            || descent < 0.0
            || line_gap < 0.0
            || advance <= 0.0
            || !height.is_finite()
            || height <= 0.0
        {
            return None;
        }
        let (ranges, tail) = self.coverage.as_chunks::<8>();
        if !tail.is_empty() {
            return None;
        }
        let mut coverage: Vec<FontRange> = Vec::new();
        for range in ranges {
            let (first, last) = range.split_at_checked(4)?;
            let first = u32::from_le_bytes(first.try_into().ok()?);
            let last = u32::from_le_bytes(last.try_into().ok()?);
            if first > last
                || last > 0x10ffff
                || coverage
                    .last()
                    .is_some_and(|previous| previous.last >= first)
            {
                return None;
            }
            coverage.push(FontRange { first, last });
        }
        let (axes, tail) = self.variations.as_chunks::<12>();
        if !tail.is_empty() {
            return None;
        }
        let mut variations = Vec::new();
        for axis in axes {
            let (tag, mut value) = axis.split_at_checked(4)?;
            if !tag.iter().all(|byte| (b' '..=b'~').contains(byte)) {
                return None;
            }
            let axis = String::from_utf8(tag.to_owned()).ok()?;
            variations.push(FontVariation {
                axis,
                value: number(&mut value)?,
            });
        }
        Some(ResolvedFont {
            request,
            data: self.data.to_owned(),
            info: FontInfo {
                ascent,
                descent,
                line_gap,
                advance,
                coverage,
            },
            variations,
        })
    }
}

fn number(bytes: &mut &[u8]) -> Option<f64> {
    let (value, rest) = bytes.split_at_checked(8)?;
    let value = f64::from_le_bytes(value.try_into().ok()?);
    *bytes = rest;
    value.is_finite().then_some(value)
}

fn payload_size(columns: &[&[u8]]) -> Option<usize> {
    columns
        .iter()
        .try_fold(0usize, |size, column| size.checked_add(column.len()))
}

fn checksum(columns: &[&[u8]]) -> [u8; 32] {
    let mut hash = Sha256::new();
    for column in columns {
        hash.update(column.len().to_le_bytes());
        hash.update(column);
    }
    hash.finalize().into()
}

#[cfg(test)]
mod tests;
