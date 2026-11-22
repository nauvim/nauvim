# Font and grid rendering

This guide describes the frontend's font selection, cell metrics and native
window geometry. These responsibilities belong to the client; the layout does
not modify `cmdheight` or install editing key mappings.

## Faces and fallback

Linux supplies installed-font candidates with Fontconfig; macOS uses CoreText
through the native runner. [Skrifa](https://github.com/googlefonts/fontations/tree/main/skrifa),
part of [Oxidize](https://github.com/googlefonts/oxidize), selects faces using
OpenType typographic names. The [font settings](configuration.md#fonts)
define name matching, explicit files, collection faces, and variable-font
default instances.

`EditorFont` preserves configuration order and each face's size. Skrifa reads
Unicode coverage and line metrics when preparing a face. Adjacent code points
are stored as compact coverage ranges. Grid glyph selection uses these
ranges; it does not open font files or call Rust for each cell. Each selected
face is loaded into Flutter under a private family alias; collection faces are
extracted into standalone OpenType data. Default variation coordinates accompany
the face's metrics and rendering style. Flutter shapes and rasterizes grid
glyphs at the selected face's configured size.

The first available face defines the grid. Larger fallback metrics do not
enlarge cells as different characters appear. Choose a primary face that gives
the desired cell dimensions. Unavailable families are skipped; if none remain,
the client resolves the system monospace family. Failed requests produce client
diagnostics and are skipped before attachment.

## Cell dimensions and baseline

The primary face's `0` advance determines cell width. Faces without a digit use
`M`, space, or their declared average/maximum advance. This follows the primary
face policy used by
[Alacritty's glyph cache](https://github.com/alacritty/alacritty/blob/791efff6d74c66bee390c259e322626ca93aadb6/alacritty/src/renderer/text/glyph_cache.rs)
and [Crossfont](https://github.com/alacritty/crossfont/blob/0c34d199b1515389bbed48a0338018e45817876e/src/ft/mod.rs).

Metrics are read in em units, then scaled by the configured font size and device
pixel ratio. Linux uses the font's preferred typographic metrics, falling back
to `hhea` according to Skrifa's selection policy. macOS prefers `hhea`, matching
CoreText. Ascent and descent are rounded outwards on Linux and to the nearest
pixel on macOS. Nonnegative line gap is rounded to the nearest pixel.

Cell width is the rounded advance, with a minimum of one physical pixel. Cell
height is ascent plus descent plus line gap, also at least one physical pixel.
The shared baseline is cell height minus descent. `EditorMetricsStyle` can add
explicit line spacing; both multipliers default to `1`.

Glyphs use their actual alphabetic baseline, not the center of their paragraph
box. All configured faces therefore share one baseline even when their sizes
differ. Neovim's continuation cells determine a glyph's allocated width. A wider
advance is reduced to that allocation; narrower advances are not enlarged.
Horizontal ink overhang is retained, with clipping at row and grid boundaries.
Tall fallback glyphs remain bounded by their row.

Filled Powerline half-circle caps (`U+E0B4`, `U+E0B6`) are drawn from the complete
cell rectangle. This follows
[Kitty's builtin cap rendering](https://github.com/kovidgoyal/kitty/blob/e9772a87252a8f807bf8b64498f4c2162a4cef2c/kitty/decorations.c#L799).
It keeps the flat edge joined to adjacent cell backgrounds regardless of font
bearings, fallback size or explicit line spacing. Other glyphs use their fonts.

## Grid and window geometry

The measured canvas is always a positive integer number of cells in each
dimension. The default design reserves exactly one additional cell row directly
below it for command input and messages. The message area grows upward over the
grid to show multiline output such as Neovim errors and `vim.notify()` messages.
Scroll inside the area to read lines that exceed the available height. The
frontend reserves its row independently of Neovim's `cmdheight`.

Initial dimensions and margins come from the frontend's selected UI opts. Integer
and `px` values use logical pixels; `em` values resolve at startup using the
measured cell width or height for the corresponding axis. See the
[window settings](configuration.md#window) for accepted values and defaults.
Flutter rounds cell-relative lengths to the nearest logical pixel at startup.
Native resize increments use the cell dimensions, with toolbar,
margins and other chrome as the base size. The runner snaps ordinary window sizes
to those increments.
GTK requires integer logical increments; when a HiDPI cell occupies a fraction
of a logical pixel, an integral group of cells supplies the increment.

Window managers can impose maximized, fullscreen or tiled bounds. The client
does not resize those states against the window manager. Its canvas still uses
whole cells, and the command row stays adjacent to the grid. Any remaining outer
space lies above or to the right of that canvas, rather than becoming another
blank row between the statusline and command input. Resize increments request
sizes from the window manager; they do not override these forced window states.

Relevant native interfaces are
[GTK geometry hints](https://docs.gtk.org/gtk3/method.Window.set_geometry_hints.html)
and `NSWindow.contentResizeIncrements`. Alacritty uses the same distinction
between [cell dimensions, grid counts and window padding](https://github.com/alacritty/alacritty/blob/791efff6d74c66bee390c259e322626ca93aadb6/alacritty/src/display/mod.rs).
