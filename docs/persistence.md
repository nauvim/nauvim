# Persistent state and font cache

## Reset saved data

Close Nauvim, delete the file for the data you want to clear, then relaunch.
Existing Neovim sessions remain available for reattachment.

| To clear | File and location |
| --- | --- |
| Remembered destination and window size | [`state.sqlite3`](#application-state-database) |
| Saved display data for reattachment | [`ui-checkpoints.sqlite3`](#session-ui-checkpoints) |
| Prepared fonts | [`fonts.sqlite3`](#location-and-recovery) |

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

Storage errors appear in the error banner. When the saved size is unavailable,
Nauvim uses the platform's default size unless you set a startup size. The next
launch creates the database if it is missing.

## Session UI checkpoints

Nauvim keeps up to 64 UI checkpoints, one per Neovim process. A checkpoint
contains display data, including text in retained grids from inactive tabs.
After you reconnect to the same Neovim process, new display updates can reuse
saved data for those grids. The checkpoint stays on the client and can be used
after you close Nauvim or restart the client.

| Platform | Location |
| --- | --- |
| Linux | `$XDG_DATA_HOME/nauvim/ui-checkpoints.sqlite3`, or `$HOME/.local/share/nauvim/ui-checkpoints.sqlite3` when no absolute XDG data directory is set |
| macOS | `$HOME/Library/Application Support/nauvim/ui-checkpoints.sqlite3` |

If no matching checkpoint is available, Nauvim attempts to attach without
saved display state. Storage errors appear in the error banner.
[Blank buffers after reattachment](troubleshooting.md#blank-buffers-after-reattachment)

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
Nauvim rebuilds a deleted cache the next time it loads fonts.

<a id="storage-design"></a>

For schema and retention details, see [persistent data for contributors](../rust/README.md#persistent-data).
