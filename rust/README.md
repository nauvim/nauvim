# Rust architecture

This crate adapts the published `nauvim-core` engine to Flutter. Core owns host
selection, transport, clipboard policy, and plugin resources. This crate owns
the application thread, action scheduling, UI snapshot projection, UI option
validation, and font preparation. Flutter owns layout, shaping, and drawing.

## Choose the layer to change

| Module | Responsibility |
| --- | --- |
| `src/api/` | Bridge entry points, serializable data, and opaque `Application` handle. |
| `src/application/` | Engine thread, bounded queues, attachment changes, input ordering, and cleanup. |
| `src/configuration/` | Selected UI dictionary validation and configuration-relative paths. |
| `src/display/` | Snapshot differences, grid placement, styles, external widgets, and ordered events. |
| `src/fonts/` | File/candidate resolution, OpenType names and variation defaults, metrics, and collection export. |
| `src/frb_generated.rs` | Generated codecs; maintained by the pinned bridge generator. |

`api` contains the public contract. Its application methods forward to the
internal handle; its font entry point borrows the incoming request/candidate
buffers for processing. Configuration and font processing depend on plain bridge
data records, without depending on Flutter sinks or the application runtime.
Implementation modules are private to the crate. Public Rust re-exports and
Dart entry points remain in `api`.

## Runtime and attachment ownership

`application::Handle` owns senders, cancellation, the cleanup acknowledgement,
and a single update receiver. Starting it creates one dedicated thread with a
current-thread Tokio runtime. `api::Application` adapts its update receiver to
Flutter's `StreamSink`; a closed sink cancels the runtime.

The driver loads configuration and emits `ready`. Startup selection waits for
Flutter's measured viewport. Grid dimensions are positive cell counts, distinct
from logical-pixel window dimensions. Further startup requests are ignored after
startup or explicit connection selection.

Control and input use separate bounded queues: 32 control actions, 256 input
actions, and 8 outgoing updates. Input processing keeps one concrete in-flight
future. Core connection attempts are initialized with one poll, then driven by
engine events so that attachment, control actions, and shutdown remain responsive.
No extra task or queue is introduced per key.

Each queued input carries its attachment epoch. Changing attachments cancels the
old epoch, drops the current input future, and drains queued input. A sender that
reserved capacity before the change still carries the cancelled epoch, so it
cannot inject stale input into a new attachment.

Shutdown cancels admission, completes core cleanup outside the driver's `select!`,
and forwards final preview-close/error events before `shutdown`. Final updates
have a bounded send wait so a missing subscriber cannot block cleanup forever.
`Application::close()` waits for the thread's acknowledgement and preserves host
Neovim processes. Queue/lifecycle failures stay concrete inside the runtime and
become strings at the bridge boundary.

Attachment initialization coalesces frames until an ordered redraw marker
confirms completion. With a sole attached UI, the adapter reinitializes its
multigrid capability at the existing viewport dimensions to clear Neovim's
cached visible normal-window contents. Restoration of the capability flags
runs before an initialization error is reported. Other attached UIs prevent
this capability reset.
Normal-window positions come from a host query carried by the completion
marker. Projection retains these positions only for the matching grid/window
pair, until Neovim supplies a placement or removes the window. For visible
floating windows, an empty `nvim_win_set_config()` update requests native
placement events without changing their configuration. These events retain
Neovim's anchor and stacking metadata; hidden floats stay hidden. Intermediate
frames stay offscreen while their ordered events are retained. Recovery adds
no per-key RPC calls or tasks.

Neovim tracks [missing window positions](https://github.com/neovim/neovim/issues/19559)
and [missing buffer contents](https://github.com/neovim/neovim/issues/30583)
separately.

## Snapshot projection

`display::Presenter` retains the previous `Arc<State>`. Grid and row identity
checks skip shared content; only changed rows materialize bridge cell strings.
Highlight changes do not copy unchanged row text. Geometry and cursor/style
projection are separate from command-line, completion, tabpage, and message
projection.

`DisplayFrame.full` requests a complete repaint; it does not require discarding
retained rows. `grids` always contains all retained grid geometry, and
`removed_grids` identifies removals since the preceding snapshot. `rows` contains
row replacements; untouched rows remain valid unless their grid was resized or
removed. `widgets = None` retains the previous widget state, while `Some([])`
clears it. Events preserve receive order independently of retained screen
snapshots and are handled once by the frontend.

Message dismissal records a snapshot of visible messages without modifying
Neovim history. The widget projector suppresses unchanged dismissed messages and
keeps the latest undo report in a coalesced burst. Prefix and cursor positions in
command-line data use UTF-8 byte offsets; Flutter converts those to UTF-16.

## Configuration and fonts

Core validates the shared option types across all UI dictionaries and selects
one using `com.naughie.nauvim.flutter` or `use_ui_opts`. The frontend's
`configuration` module validates the selected options and resolves relative
font paths against the loaded configuration's canonical directory. Core applies
the complete defaults when its validation or the frontend's schema parser
fails. Flutter resolves window geometry from measured editor cells. See the
[configuration reference](../docs/configuration.md#ui-options) for option syntax
and defaults.

Font processing is separate from the async engine. `source` owns file reads and
a bounded one-file candidate buffer. `selection` handles OpenType face/name and
axis-default rules. `metrics` reads borrowed font tables. `sfnt` extracts collection
faces with `write-fonts`, rebuilding offsets/checksums and omitting signatures
that no longer authenticate the extracted binary. `cache` persists prepared faces
in SQLite after source selection. It reuses metrics, coverage, variation defaults,
and collection exports. Standalone font buffers move into the bridge.
[Font and grid rendering](../docs/fonts-and-grid.md) explains how Flutter turns
these metrics into cells and baselines.

## Persistent data

`application/history` commits the last requested destination before starting
a connection. Its single selection row distinguishes a null alias for the
default local host from a named alias. An empty table indicates no saved
destination. A storage failure leaves host connections available.

`fonts/cache` keys prepared faces by source content, selected face index, platform,
architecture, and font-processing revision. Advance that revision when changes
affect prepared output. Reads verify the payload checksum and decoded values.
Each write and its evictions form one transaction. The cache keeps up to 128
entries and 64 MiB of payload, evicting the least recently used. That limit
applies to payload, while SQLite manages the database file and journal.

Both stores use bundled SQLite with a 25 ms busy timeout. Their application IDs
are `0x4e415553` for host selection and `0x4e415546` for the font cache. Each
checks its schema version with `user_version` and preserves foreign or
unsupported databases. The [saved data guide](../docs/persistence.md) lists paths
and reset instructions.

## Tests and generated code

Focused tests live with their implementation modules. Application tests cover
cancellation, bounded queues, configuration diagnostics, and the live host
workflow. Display tests check snapshot reuse, changed rows, floating placement,
widgets, and event order. Font tests use an original generated fixture and
constructed collections/variation tables rather than installed-font assumptions.

The opt-in rendering regressions check the first projected frame after
reattachment. They cover split-buffer contents and saved views, bordered and
overlapping floats, hidden floats, and terminal-float contents and mode. They
also check that recovery preserves window configuration and editor options.
These tests verify recovery from omitted state in Neovim v0.12.6; connection
reuse alone does not verify rendering. See
[reattachment troubleshooting](../docs/troubleshooting.md#blank-buffers-after-reattachment).

Use the [development guide](../docs/development.md) for commands and prerequisites.
Regenerate both bridge sides after changing the public contract, and inspect the
result when moving implementation code. Internal refactoring must not add cell
copies, dynamic dispatch, input tasks, or unbounded caches.
