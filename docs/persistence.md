# Persistent font cache

## Storage scope

Nauvim persists prepared fonts owned by the Flutter frontend. Each entry contains
the selected standalone SFNT bytes, metrics in em units, Unicode coverage, and
default variation axes. These values are rebuildable from local font files.
Losing this cache affects preparation time; it does not lose application state.

Font discovery and source selection still run for every resolution. This keeps
native preference order, exact OpenType name matching, and missing-file errors
current. The cache saves metrics and coverage inspection and collection-face
extraction. It does not replace source-file reads or platform font discovery.

An entry belongs to the exact source bytes and selected collection face, within
one platform and font-processing revision. Its identity excludes request order,
configured size, display scale, and Flutter's temporary family alias. The
current request index is attached when the prepared face is returned. Resolution
reads an entry after selecting the source face and writes it after successful
preparation. Entries may be evicted or deleted at any time.

Lua remains the source of configuration. Window geometry is not stored: the
current initial-size contract comes from UI options and platform window policy,
and restoration would need its own precedence and multi-window policy. Sessions
are not stored by this frontend: `nauvim-core` owns host selection, socket
discovery, session eligibility, and surviving Neovim processes. A second session
registry would duplicate that ownership. No restoration state is selected for
SQLite in this implementation.

## Location and recovery

The database is `nauvim/fonts.sqlite3` beneath the platform cache directory:

| Platform | Location |
| --- | --- |
| Linux | `$XDG_CACHE_HOME/nauvim/fonts.sqlite3`, or `$HOME/.cache/nauvim/fonts.sqlite3` when no absolute XDG cache directory is set |
| macOS | `$HOME/Library/Caches/nauvim/fonts.sqlite3` |

The directory and database are created when fonts are resolved. The location is
shared across configurations for the same operating-system user. Source files
are read on every resolution, and their SHA-256 content digest identifies the
prepared result. Replacing or removing a source therefore takes effect on the
next resolution, even if file size and modification time are unchanged.

A missing entry is prepared normally and inserted after success. Damaged entry
payloads are discarded and rebuilt from the selected source. An unavailable,
locked, unreadable, or incompatible database adds a cache diagnostic to the
client error display; usable fonts still load from their source files. A storage
operation failure disables cache use for the rest of that resolution. Later
resolutions try opening the cache again. Font selection errors retain their
existing skip-and-fallback behavior.

The database contains only rebuildable cache data. To clear it or recover from
database corruption, close Nauvim and delete `fonts.sqlite3` from the location
above. The next font resolution recreates it. Nauvim does not delete an unreadable
database or overwrite an unknown schema automatically.

## Storage design

The Rust font-processing layer uses synchronous `rusqlite` with bundled SQLite.
This keeps storage beside preparation without an async runtime, connection pool,
or new background task. A resolution opens one connection with a 25 ms SQLite
busy timeout. Each write and its retention changes form one transaction. Readers
and writers use SQLite's rollback journal and locking.

Schema version 1 uses SQLite `user_version` and application ID `0x4e415546`.
The `fonts` table stores a digest key, exported font bytes, metrics, coverage,
variation axes, a payload checksum, and a recency counter. Binary numeric fields
use little-endian encoding. The checksum covers the length-delimited output
fields. Lookup validates the checksum and decoded values before returning a face.
Request indices are attached from the current call rather than stored.

Keys include source content, selected face index, operating system, architecture,
and a font-processing revision. Changes to selection/export semantics, metric
policy, or dependency behavior that affect prepared output require advancing the
processing revision. Entries from another revision cannot satisfy a lookup.

An empty database is initialized transactionally. Databases with another
application ID, an unsupported schema version, or existing unversioned tables
are rejected and preserved. There is no earlier Nauvim schema to migrate.
Future schema changes must define supported migrations and advance `user_version`;
an older build must continue to preserve newer databases.

Retention keeps at most 128 entries and 64 MiB of payload, evicting the least
recently used entries after writes. A successful lookup updates recency. An
entry larger than the payload budget is used for the current resolution without
being cached. Old source versions expire through the same retention policy.
The payload budget does not bound the database's physical size: SQLite may retain
free pages and create a rollback journal during a transaction.
