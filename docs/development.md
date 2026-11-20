# Develop and validate Nauvim

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

The rendering regressions check the first returned frame after reattachment,
before further input. They cover split buffers, bordered overlapping floats
with fractional and window-relative positions, equal-priority stacking, hidden
floats, and a terminal float that remains in terminal mode:

```sh
NVIM_BIN=/absolute/path/to/nvim cargo test --manifest-path rust/Cargo.toml live_restores_ -- --ignored
```

The tests also check that window geometry, floating-window configuration, saved
views, selected editor options, and multigrid support survive recovery. They
remain opt-in because they start real Neovim processes; the terminal test also
requires `/bin/sh`. All live workflows can be run together with
`-- --include-ignored`. See
[reattachment troubleshooting](troubleshooting.md#blank-buffers-after-reattachment)
for the Neovim protocol defects that require initialization recovery.

## Native runner checks

On Linux, check renderer selection and GPU discovery without a display:

```sh
cmake -S linux/runner/tests -B build/linux-renderer-tests
cmake --build build/linux-renderer-tests
ctest --test-dir build/linux-renderer-tests --output-on-failure
```

## Desktop integration

After building a release bundle, run the desktop integration check on a graphical
desktop with Neovim v0.12.6:

```sh
python3 tool/smoke.py --nvim /absolute/path/to/nvim
```

It uses isolated configuration, sockets, and temporary directories. It checks
attachment, structured completion updates, native HTTP preview access,
detachment, SIGTERM cleanup, and reuse of the same surviving host process.
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
