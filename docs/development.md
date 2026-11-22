# Develop and validate Nauvim

## Run a debug build

Set up the platform prerequisites in the [build guide](building.md). Run
`tool/run.sh -d linux` or `tool/run.sh -d macos` from the repository root.
Restart the script after Rust changes to rebuild the debug library.

## Rust and Flutter checks

Run these commands from the repository root:

```sh
cargo fmt --manifest-path rust/Cargo.toml --check
cargo test --manifest-path rust/Cargo.toml
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
flutter analyze
flutter test
```

The regular Rust suite covers projection, configuration, font selection, and
in-memory lifecycle cases. To include the test that starts isolated Neovim
hosts and checks input ordering, malformed `msg_showcmd` handling, host switching,
and cleanup:

```sh
NVIM_BIN=/absolute/path/to/nvim cargo test --manifest-path rust/Cargo.toml live_orders_input -- --ignored
```

The startup rendering regressions check the first returned frame after
reattachment, before further input. They cover split buffers, bordered
overlapping floats with fractional and window-relative positions, equal-priority
stacking, hidden floats, and a terminal float that remains in terminal mode. The
tab-switch regression checks that the selected buffer becomes visible, the
previous tab is hidden, and the same Neovim process stays attached.

```sh
NVIM_BIN=/absolute/path/to/nvim cargo test --manifest-path rust/Cargo.toml live_restores_ -- --ignored
NVIM_BIN=/absolute/path/to/nvim cargo test --manifest-path rust/Cargo.toml live_switches_tabs -- --ignored
```

The tests also check that window geometry, floating-window configuration, saved
views, selected editor options, and multigrid support survive recovery. They
remain opt-in because they start real Neovim processes; the terminal test also
requires `/bin/sh`. All live workflows can be run together with
`-- --include-ignored`. The
[attachment design](../rust/README.md#runtime-and-attachment-ownership)
describes the Neovim issues behind these cases.

## Native runner checks

On Linux, build the native tests and check renderer selection, GPU discovery,
and window options:

```sh
cmake -S linux/runner/tests -B build/linux-renderer-tests
cmake --build build/linux-renderer-tests
ctest --test-dir build/linux-renderer-tests --output-on-failure
```

The window-option tests check dimensions, decorations, opacity, and pending mode
transitions through GTK. They require a GTK display and report a skip without one.
GTK's Broadway backend can run these tests on a headless display; it does not
validate a desktop window manager's acceptance of maximized/fullscreen requests
or the final composited window appearance.

On macOS, the `RunnerTests` target checks native window appearance and dimensions.
Run it in Xcode on macOS. Also check native zoom, fullscreen entry/exit, and
borderless keyboard focus interactively. Linux builds and GTK tests do not
validate AppKit behavior.

## Desktop integration

After building a release bundle, run the desktop integration check on a graphical
desktop with Neovim v0.12.6:

```sh
python3 tool/smoke.py --nvim /absolute/path/to/nvim
```

It uses isolated configuration, sockets, and temporary directories. It loads
custom welcome, clipboard, and webview bindings through the real bridge. The
check covers attachment, structured completion updates, native HTTP preview
access, blocked preview redirects, detachment, SIGTERM cleanup, and reuse of
the same surviving host process.
It stops its test-owned hosts afterward.
The smoke check verifies connection and process reuse; it does not inspect
buffer pixels. Use the rendering regression above to check received buffer
visibility and contents. macOS builds and desktop behaviour require validation
on macOS.

## Regenerate bridge bindings

Bindings are checked in. After changing the Rust bridge contract in
`rust/src/api`, regenerate both sides with the matching generator:

```sh
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
tool/generate.sh
```

The generator owns `rust/src/frb_generated.rs` and `lib/src/bridge/`. Do not edit
their codecs by hand. Implementation-only Rust changes keep the bridge contract;
regenerate after a structural refactor to confirm the generated interface still
matches. See the [Rust architecture guide](../rust/README.md) and
[Flutter design guide](architecture.md) for module boundaries.
