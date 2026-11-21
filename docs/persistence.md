# Persistent state and font cache

## Host selection

The welcome page remembers the last destination you requested across launches,
including failed or cancelled connection attempts. A saved alias outside the
host list is restored under **Type yourself**, ready to edit or submit.
Automatic connections follow the startup rules in your configuration.
[Hosts and startup](configuration.md#hosts-and-startup)

Nauvim shares the saved destination across configurations for your OS account.

| Platform | Location |
| --- | --- |
| Linux | `$XDG_DATA_HOME/nauvim/state.sqlite3`, or `$HOME/.local/share/nauvim/state.sqlite3` when no absolute XDG data directory is set |
| macOS | `$HOME/Library/Application Support/nauvim/state.sqlite3` |

Storage errors appear in the error display, and you can still connect. To reset
the selection or recover from a damaged database, close Nauvim and delete
`state.sqlite3`. The next launch creates a new database. You can still reattach
to existing Neovim sessions.

## Font cache

<a id="storage-scope"></a>

Nauvim caches prepared fonts to speed up later launches. Replacing or removing
a font file takes effect the next time Nauvim loads fonts.

### Location and recovery

| Platform | Location |
| --- | --- |
| Linux | `$XDG_CACHE_HOME/nauvim/fonts.sqlite3`, or `$HOME/.cache/nauvim/fonts.sqlite3` when no absolute XDG cache directory is set |
| macOS | `$HOME/Library/Caches/nauvim/fonts.sqlite3` |

If the cache is unavailable, usable fonts still load from their source files.
To clear the cache or recover from a damaged database, close Nauvim and delete
`fonts.sqlite3`. Nauvim rebuilds it the next time it loads fonts.

<a id="storage-design"></a>

For schema and retention details, see [persistent data for contributors](../rust/README.md#persistent-data).
