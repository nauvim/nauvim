use super::*;

const DATA: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../test/fixtures/grid_test.ttf"
));

fn font() -> ResolvedFont {
    super::super::export(0, DATA.to_vec(), 0).unwrap()
}

#[test]
fn reuses_standalone_source_bytes_on_a_cache_hit() {
    let directory = tempfile::tempdir().unwrap();
    let mut cache = Cache::open(directory.path().join("fonts.sqlite3")).unwrap();
    let key = Key::new(DATA, 0);
    cache.put(&key, &font()).unwrap();

    let data = DATA.to_vec();
    let buffer = data.as_ptr();
    let hit = cache.get(&key, &data).unwrap().unwrap().into_font(7, data);

    assert_eq!(hit.request, 7);
    assert_eq!(hit.data, DATA);
    assert_eq!(hit.data.as_ptr(), buffer);
}

#[test]
fn preserves_foreign_future_and_unversioned_databases() {
    for (application, version) in [
        (APPLICATION_ID, SCHEMA_VERSION + 1),
        (123, SCHEMA_VERSION),
        (0, 0),
    ] {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("fonts.sqlite3");
        let conn = Connection::open(&path).unwrap();
        conn.execute_batch(
            "CREATE TABLE saved (value TEXT); INSERT INTO saved VALUES ('retained')",
        )
        .unwrap();
        conn.pragma_update(None, "application_id", application)
            .unwrap();
        conn.pragma_update(None, "user_version", version).unwrap();
        drop(conn);

        let before = fs::read(&path).unwrap();
        assert!(
            Cache::open(path.clone()).is_err(),
            "{application}, {version}"
        );
        assert_eq!(fs::read(&path).unwrap(), before, "{application}, {version}");
    }
}

#[test]
fn preserves_corrupt_databases_and_rejects_incomplete_owned_schemas() {
    let directory = tempfile::tempdir().unwrap();
    let corrupt = directory.path().join("corrupt.sqlite3");
    fs::write(&corrupt, b"not a SQLite database").unwrap();
    assert!(Cache::open(corrupt.clone()).is_err());
    assert_eq!(fs::read(&corrupt).unwrap(), b"not a SQLite database");

    let incomplete = directory.path().join("incomplete.sqlite3");
    let conn = Connection::open(&incomplete).unwrap();
    conn.pragma_update(None, "application_id", APPLICATION_ID)
        .unwrap();
    conn.pragma_update(None, "user_version", SCHEMA_VERSION)
        .unwrap();
    drop(conn);
    let before = fs::read(&incomplete).unwrap();
    assert!(Cache::open(incomplete.clone()).is_err());
    assert_eq!(fs::read(&incomplete).unwrap(), before);
}

#[test]
fn deletes_damaged_payloads_and_rejects_invalid_decoded_values() {
    let directory = tempfile::tempdir().unwrap();
    let mut cache = Cache::open(directory.path().join("fonts.sqlite3")).unwrap();
    let key = Key::new(DATA, 0);
    let font = font();

    for damage in [
        "data",
        "checksum",
        "metrics",
        "coverage_length",
        "coverage_order",
        "variation_tag",
        "variation_value",
    ] {
        cache.put(&key, &font).unwrap();
        let (mut data, mut metrics, mut coverage, mut variations, mut stored_checksum) = cache
            .conn
            .query_row(
                "SELECT data, metrics, coverage, variations, checksum FROM fonts WHERE key = ?1",
                [&key.0[..]],
                |row| {
                    Ok((
                        row.get::<_, Vec<u8>>(0)?,
                        row.get::<_, Vec<u8>>(1)?,
                        row.get::<_, Vec<u8>>(2)?,
                        row.get::<_, Vec<u8>>(3)?,
                        row.get::<_, Vec<u8>>(4)?,
                    ))
                },
            )
            .unwrap();
        match damage {
            "data" => data.push(0),
            "checksum" => stored_checksum.clear(),
            "metrics" => metrics = [f64::NAN.to_le_bytes(); 4].concat(),
            "coverage_length" => coverage = vec![0],
            "coverage_order" => {
                coverage = [4u32, 8, 7, 9]
                    .into_iter()
                    .flat_map(u32::to_le_bytes)
                    .collect();
            }
            "variation_tag" => {
                variations = b"wg\x01t".to_vec();
                variations.extend(650f64.to_le_bytes());
            }
            "variation_value" => {
                variations = b"wght".to_vec();
                variations.extend(f64::INFINITY.to_le_bytes());
            }
            _ => panic!("unknown damage: {damage}"),
        }
        if !matches!(damage, "data" | "checksum") {
            stored_checksum = checksum(&[&data, &metrics, &coverage, &variations]).into();
        }
        cache
            .conn
            .execute(
                "UPDATE fonts SET data = ?2, metrics = ?3, coverage = ?4, variations = ?5,
                     checksum = ?6 WHERE key = ?1",
                (
                    &key.0[..],
                    &data,
                    &metrics,
                    &coverage,
                    &variations,
                    &stored_checksum,
                ),
            )
            .unwrap();

        assert!(cache.get(&key, DATA).unwrap().is_none(), "{damage}");
        assert_eq!(
            cache
                .conn
                .query_row("SELECT count(*) FROM fonts", [], |row| row.get::<_, i64>(0))
                .unwrap(),
            0,
            "{damage}"
        );
    }
}

#[test]
fn evicts_the_least_recently_used_entry_at_the_count_limit() {
    let directory = tempfile::tempdir().unwrap();
    let mut cache = Cache::open(directory.path().join("fonts.sqlite3")).unwrap();
    let font = font();
    let key = |idx: i64| Key::new(&idx.to_le_bytes(), 0);
    for idx in 0..MAX_ENTRIES {
        cache.put(&key(idx), &font).unwrap();
    }
    assert!(cache.get(&key(0), DATA).unwrap().is_some());
    cache.put(&key(MAX_ENTRIES), &font).unwrap();

    assert!(cache.get(&key(0), DATA).unwrap().is_some());
    assert!(cache.get(&key(1), DATA).unwrap().is_none());
    assert!(cache.get(&key(MAX_ENTRIES), DATA).unwrap().is_some());
    assert_eq!(
        cache
            .conn
            .query_row("SELECT count(*) FROM fonts", [], |row| row.get::<_, i64>(0))
            .unwrap(),
        MAX_ENTRIES
    );
}

#[test]
fn enforces_the_payload_budget_when_inserting_a_font() {
    let directory = tempfile::tempdir().unwrap();
    let mut cache = Cache::open(directory.path().join("fonts.sqlite3")).unwrap();
    let older = Key::new(b"older", 0);
    let newer = Key::new(b"newer", 0);
    for (key, used) in [(&older, 1), (&newer, 2)] {
        cache
            .conn
            .execute(
                "INSERT INTO fonts VALUES (?1, zeroblob(?2), x'', x'', x'', zeroblob(32), ?3)",
                (&key.0[..], MAX_BYTES / 2 + 1024, used),
            )
            .unwrap();
    }
    let current = Key::new(DATA, 0);
    cache.put(&current, &font()).unwrap();

    let contains = |key: &Key| {
        cache
            .conn
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM fonts WHERE key = ?1)",
                [&key.0[..]],
                |row| row.get::<_, bool>(0),
            )
            .unwrap()
    };
    assert!(!contains(&older));
    assert!(contains(&newer));
    assert!(contains(&current));
    let bytes: usize = cache
        .conn
        .query_row(
            "SELECT sum(length(data) + length(metrics) + length(coverage) + length(variations))
             FROM fonts",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert!(bytes <= MAX_BYTES);
}

#[test]
fn skips_oversized_faces_without_evicting_existing_entries() {
    let directory = tempfile::tempdir().unwrap();
    let mut cache = Cache::open(directory.path().join("fonts.sqlite3")).unwrap();
    let existing = Key::new(DATA, 0);
    let mut font = font();
    cache.put(&existing, &font).unwrap();
    font.data = vec![0; MAX_BYTES + 1];
    let oversized = Key::new(b"oversized", 0);
    cache.put(&oversized, &font).unwrap();
    assert!(cache.get(&oversized, DATA).unwrap().is_none());
    assert!(cache.get(&existing, DATA).unwrap().is_some());
}
