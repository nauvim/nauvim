# Troubleshooting

## Display and rendering

The default renderer is Flutter's GPU backend. On X11, the unpatched Flutter
3.50.0 engine has an [upstream compositor defect](https://github.com/flutter/flutter/issues/195885)
that can shift the UI outside the window with a sole NVIDIA adapter. Nauvim's
Linux runner automatically selects software rendering for that combination.
Builds with the [corrected engine](https://github.com/flutter/flutter/pull/196418)
retain GPU rendering automatically.

An explicit `FLUTTER_LINUX_RENDERER` takes precedence. To select software
rendering, which uses the CPU:

```sh
FLUTTER_LINUX_RENDERER=software build/linux/x64/release/bundle/nauvim
```

The runner selects Skia text for Flutter's software canvas. The same variable
works with `tool/run.sh` and `tool/smoke.py`.

For spacing or fallback selection, first check the
[font selection rules](../README.md#appendix-opentype-font-selection). Window
managers can impose maximized or tiled sizes that do not fit whole cells; the
[geometry guide](fonts-and-grid.md#grid-and-window-geometry) explains the remaining
outer space.

## Configuration errors

Configuration diagnostics appear in the client error display. Lua loading errors
or invalid selected UI opts cause core to use its complete default configuration,
including host settings. An unresolved font request instead skips that font and
preserves the host configuration.

Check the [UI schema](../README.md#configuration-and-connections), especially the
UI implementation ID, integer dimensions, and typographic font names. Relative
font paths use the canonical configuration file's directory.

## Input and connection behavior

Editing mappings belong to Neovim. Nauvim intercepts only platform copy/paste
shortcuts while editing. Native IME composition is not implemented.

Detaching or closing the GUI preserves host Neovim processes for reattachment.
A host exit or connection failure returns to the welcome page. Use the error
display to identify the failing operation, then select the host again. See
[editing and lifecycle](../README.md#editing-and-lifecycle) for connection and
shutdown behavior.

### Blank buffers after reattachment

Neovim v0.12.6 can omit window positions and unchanged window contents when a
multigrid UI reattaches at the same size. The statusline can remain visible while
the buffers are blank. Later redraws can reveal only parts of a buffer. The host
and its buffers remain running.

Nauvim holds initialization frames until the redraw is complete and restores
normal-window positions from Neovim's window API. It requests native placement
events for visible floating windows, retaining their configuration, anchors,
and stacking order. Hidden floats remain hidden. When it is the host's only
attached UI, it also reinitializes its multigrid capability at unchanged window
dimensions to obtain uncached contents. This restores the UI capability flags
before presenting the editor and does not set `cmdheight` or other editor
configuration options. With other attached UIs, it restores positions without
resetting shared rendering capabilities; the Neovim contents defect can still
affect that case.

After Rust changes, rebuild with `tool/build.sh` and restart Nauvim. An already
running process keeps its loaded Rust library. Flutter hot reload does not
replace that library. See the [build guide](building.md).

The missing positions are tracked in
[Neovim #19559](https://github.com/neovim/neovim/issues/19559), and the missing
contents in [Neovim #30583](https://github.com/neovim/neovim/issues/30583).
[Neovim #42667](https://github.com/neovim/neovim/pull/42667) addresses contents;
it explicitly leaves the position issue unresolved. The
[development guide](development.md#rust-and-flutter-checks)
includes opt-in regressions that check split buffers, floating windows, and
terminal-float contents and mode after reattachment, before any editing input.
