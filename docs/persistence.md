# Persistent state and font cache

## Host selection

Nauvim stores the last requested destination in SQLite before beginning its
connection attempt. The default local host is a separate choice from every
alias, including `local`, `Local`, and `default`. Failed or cancelled attempts
retain the requested choice. Returning to the welcome page after Neovim quits
or detaches selects that destination again.

The next Nauvim process restores this selection on the welcome page. An alias
outside the current configuration is restored under **Type yourself**, with the
alias ready to edit or submit. Restoring the selection does not connect to the
host. Lua's `default_host` and the automatic default local connection with no
configured hosts keep their existing startup behavior. An automatic startup
connection or a host switch requested by the Neovim plugin also saves its
destination.

The database is `nauvim/state.sqlite3` beneath the platform local data directory:

| Platform | Location |
| --- | --- |
| Linux | `$XDG_DATA_HOME/nauvim/state.sqlite3`, or `$HOME/.local/share/nauvim/state.sqlite3` when no absolute XDG data directory is set |
| macOS | `$HOME/Library/Application Support/nauvim/state.sqlite3` |

The selection is shared across configurations for the same operating-system
user. It stores only a destination, without duplicating core's host process or
session registry. Window geometry remains governed by UI options and platform
window policy.

The application driver opens one synchronous `rusqlite` connection with a 25 ms
busy timeout. Schema version 1 uses application ID `0x4e415553` and SQLite
`user_version`. The `selection` table holds one row: a null alias means the
default local host; a nonempty alias names a configured or manually entered
host. An empty table means there is no saved choice. Each selection is committed
when requested, so it does not depend on orderly process shutdown.

An unavailable, locked, damaged, or incompatible database produces a diagnostic
without preventing connections. If opening fails, persistence is disabled for
that process; the next launch tries again. A failed write leaves the previous
selection stored. Unknown application IDs, unsupported schema versions, and
occupied unversioned databases are preserved. To reset the saved selection or
recover from corruption, close Nauvim and delete `state.sqlite3`. The next
launch creates a fresh database. This does not remove host sessions or the font
cache.

## Font cache

### Storage scope

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

Lua remains the source of configuration. `nauvim-core` owns socket discovery,
session eligibility, and surviving Neovim processes.

### Location and recovery

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

### Storage design

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
