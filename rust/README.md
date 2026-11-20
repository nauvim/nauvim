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

Core selects UI opts using `com.naughie.nauvim.flutter` or `use_ui_opts`.
`configuration` validates only the frontend's schema, then resolves relative
font paths against the loaded configuration's canonical directory. Schema errors
follow core's complete-default fallback. The [user README](../README.md#configuration-and-connections)
is the authoritative schema reference.

Font processing is separate from the async engine. `source` owns file reads and
a bounded one-file candidate cache. `selection` handles OpenType face/name and
axis-default rules. `metrics` reads borrowed font tables. `sfnt` extracts collection
faces with `write-fonts`, rebuilding offsets/checksums and omitting signatures
that no longer authenticate the extracted binary. Standalone font buffers move
into the bridge unchanged. Font discovery performs no per-cell I/O.

The [OpenType appendix](../README.md#appendix-opentype-font-selection) defines
selection behavior. [Font and grid rendering](../docs/fonts-and-grid.md) explains
how Flutter turns these metrics into cells and baselines.

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
