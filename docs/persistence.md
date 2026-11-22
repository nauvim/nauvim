# Persistent state and font cache

## Host selection

The welcome page remembers the last destination you requested across launches,
including failed or cancelled connection attempts. A saved alias outside the
host list is restored under **Type yourself**, ready to edit or submit.
Automatic connections follow the startup rules in your configuration.
[Hosts and startup](configuration.md#hosts-and-startup)

## Window size

Nauvim saves the latest client-area width and height in whole logical pixels
during an orderly shutdown. On the next launch, Nauvim restores that size when
`window.startup_size` is omitted or `nil`. Explicit dimensions and startup modes
take precedence. See [window configuration](configuration.md#window).

## Application state database

Nauvim shares the saved destination and window size across configurations for
your OS account.

| Platform | Location |
| --- | --- |
| Linux | `$XDG_DATA_HOME/nauvim/state.sqlite3`, or `$HOME/.local/share/nauvim/state.sqlite3` when no absolute XDG data directory is set |
| macOS | `$HOME/Library/Application Support/nauvim/state.sqlite3` |

Storage errors appear in the error display. You can still connect and start
with the platform's default size when the saved size is unavailable. To clear
the saved destination and size or recover from a damaged database, close Nauvim
and delete `state.sqlite3`. The next launch creates a new database. You can still
reattach to existing Neovim sessions.

## Session UI checkpoints

Nauvim keeps up to 64 UI checkpoints, one per Neovim process. A checkpoint contains
the display state, including text in retained grids from inactive tabs. When you
reconnect to the same Neovim process, Nauvim uses this state to restore the
first display. The checkpoint stays on the client and can be used after you
close Nauvim or restart the client.

| Platform | Location |
| --- | --- |
| Linux | `$XDG_DATA_HOME/nauvim/ui-checkpoints.sqlite3`, or `$HOME/.local/share/nauvim/ui-checkpoints.sqlite3` when no absolute XDG data directory is set |
| macOS | `$HOME/Library/Application Support/nauvim/ui-checkpoints.sqlite3` |

If no matching checkpoint is available, Nauvim attempts to attach without
saved display state. Storage errors appear in the error display. To clear the
checkpoints, close Nauvim and delete `ui-checkpoints.sqlite3`. See
[blank buffers after reattachment](troubleshooting.md#blank-buffers-after-reattachment)
for a Neovim reattachment limitation when no checkpoint is available.

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
