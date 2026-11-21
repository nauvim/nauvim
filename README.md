# Nauvim

A Flutter desktop GUI for Neovim on Linux and macOS. Connect to local or SSH
hosts, detach, and reattach to the same surviving editor process.

## Requirements

- Flutter 3.50 or newer, Dart 3.14 or newer, and Rust 1.89 or newer.
- Neovim v0.12.6 in each host environment.
- Linux x86-64/aarch64 or macOS Apple Silicon, with the native build dependencies
  listed in the [build guide](docs/building.md).
- A compatible `nauvim-plugin` in the host Neovim for plugin requests and
  clipboard-provider integration. Ordinary editing works without it.

## Build and run

From this directory:

```sh
flutter pub get
tool/build.sh
```

Run `build/linux/x64/release/bundle/nauvim` on Linux x86-64, or
`build/linux/arm64/release/bundle/nauvim` on aarch64. On macOS, open
`build/macos/Build/Products/Release/Nauvim.app`. Move the complete release bundle
when installing it elsewhere; it includes the Rust library.

See [building and running](docs/building.md) for native prerequisites and
development runs. For shifted UI or renderer selection, see
[display troubleshooting](docs/troubleshooting.md#display-and-rendering).

## Configuration and connections

Nauvim reads the platform configuration directory's `nauvim/init.lua`
(`$XDG_CONFIG_HOME/nauvim/init.lua` when that variable is set). Supply an explicit
file with `nauvim --config /absolute/path/init.lua`.

For example:

```lua
return {
    hosts = {
        laptop = {},
        work = { ssh = { host_name = "work.example.com" } },
    },
    ui_opts = {
        ["com.naughie.nauvim.flutter"] = {
            fonts = {
                { family = "monospace", size = 14 },
            },
            window = {
                width = "1920px",
                height = "40em",
                decorations = "full",
                opacity = 1.0,
                startup_mode = "windowed",
                margin = { top = "0.5em", bottom = "1em", left = 8, right = "8px" },
            },
        },
    },
}
```

### UI options

The UI implementation ID is `com.naughie.nauvim.flutter`. The core selects its
entry from `ui_opts`, or the entry selected by `use_ui_opts`. Fonts and window
settings belong inside that entry.

The accepted UI option schema is:

```text
Font = {
    family: string,
    subfamily: string | nil,
    size: positive integer | nil,
    path: string | nil,
}

Length = integer | "<integer>px" | "<number>em"

UiOpts = {
    fonts: string | Font | list[Font] | nil,
    key_bindings: table | nil,
    window: {
        width: positive Length | nil,
        height: positive Length | nil,
        decorations: "full" | "none" | nil,
        opacity: number in [0, 1] | nil,
        startup_mode: "windowed" | "maximized" | "fullscreen" | nil,
        margin: {
            top: nonnegative Length | nil,
            bottom: nonnegative Length | nil,
            left: nonnegative Length | nil,
            right: nonnegative Length | nil,
        } | nil,
    } | nil,
}
```

A font string is shorthand for `{ family = "..." }`. Omitted font sizes use
15 logical pixels. An omitted or empty font list uses the system monospace
font at that size. See the [OpenType selection appendix](#appendix-opentype-font-selection)
for the exact meaning of `family`, `subfamily`, and `path`.
Font sizes remain positive Lua integers within the unsigned 32-bit range.
Window dimensions and margins accept Lua integers in that range, integer pixel
strings such as `"1920px"`, or finite cell-relative numbers such as `"100em"`
and `"0.5em"`. Dimensions must be positive; margins can be zero. A `px` string
contains decimal digits only before the suffix, so `"0.5px"` is invalid. An `em`
number can include a decimal fraction or exponent, such as `"1e2em"`. Unit
suffixes are lowercase and strings cannot contain whitespace. Bare Lua fractions
such as `width = 100.5` remain invalid; use an explicit `em` string for fractions.

Integer and `px` values use **logical pixels**: Flutter logical pixels, GTK logical
coordinates on Linux, and AppKit points on macOS. The display scale converts
these to physical pixels. Font size specifies the em size in the same unit.
Window width and height are the initial client-area size, including Nauvim's
toolbar and margins, and excluding operating-system window decorations.
An omitted dimension keeps the platform's initial size. Margins default to zero
and surround the editor grid and its command row. Cell resize increments can
adjust the requested size to fit whole cells; window-manager constraints still
apply.

For horizontal geometry (`width`, `margin.left`, and `margin.right`), `1em` is
one editor cell width. For vertical geometry (`height`, `margin.top`, and
`margin.bottom`), it is one editor cell height. These are the measured cells of
the selected font, including display-scale rounding and any design-supplied line
spacing; they are not the font's em size. For example, `width = "100em"` requests
a client area 100 cell widths wide, still including toolbar space and margins;
it does not request exactly 100 editor columns.

Cell-relative geometry is resolved once at startup after measuring the selected
font. Results are rounded to the nearest logical pixel, with half pixels rounded
up. Dimensions are at least one logical pixel, and resolved values are capped at
4294967295. Later window resizing or cell-metric changes do not reapply these
startup values. Omitted dimensions retain the platform's initial size, and
omitted margins remain zero.

`window.opacity` accepts finite Lua integers or numbers from 0 (invisible) to 1
(opaque). It defaults to 1 and affects the whole window:
backgrounds, text, cursors, controls, and native HTTP previews. It is not a
background-only transparency setting. Native decorations follow platform
compositing policy. Linux requires
[compositor support](https://docs.gtk.org/gtk3/method.Widget.set_opacity.html);
an unsupported opacity request can leave the window opaque. Opacity does not
change input handling.

`decorations` defaults to `"full"`, with the native title bar and controls.
`"none"` requests a borderless window; Nauvim does not add replacement title-bar
drag or resize handles. Use the window manager's controls or shortcuts as needed.
Linux decoration and startup-mode requests are subject to
[window-manager policy](https://docs.gtk.org/gtk3/method.Window.set_decorated.html).

`startup_mode` defaults to `"windowed"`. `"maximized"` requests the platform's
maximized state (native zoom on macOS); `"fullscreen"` requests native fullscreen.
Width and height set the windowed content size before the startup-mode request.
Margins apply in every mode. Cell-size snapping does not resize a maximized or
fullscreen window. Snapping also waits for the initial mode transition; on Linux
it resumes after a bounded wait if the window manager does not confirm the mode.

All window options apply once after configuration loads. Editing `init.lua`
requires restarting Nauvim; later user resizing and mode changes are retained.
Window geometry is not restored from storage, so there is no restored-state
precedence. Unknown option names, unsupported values, and invalid types follow
the complete-configuration fallback described below.

Configuration is evaluated in client-side Lua 5.4. Its sibling `lua/` directory
is searched for configuration modules. Lua loading errors and invalid selected
UI opts appear in the client error display and replace the entire configuration,
including host settings, with core's defaults. Font-file discovery failures are
diagnosed separately and do not discard the host configuration. See the
[core configuration reference](https://github.com/nauvim/nauvim-core/blob/main/docs/usage.md)
for program arguments, socket paths, SSH settings, clipboard backends, and
host policies.

### Connections and welcome keys

With configured hosts and no `default_host`, the welcome page offers those
aliases and a separate default local host. You can also enter an SSH alias.
Selecting a destination starts or resumes its eligible owned session. A named
alias called `local` or `default` remains distinct from the default local choice.
Set `default_host = "work"` to connect there automatically at startup. With no
host configuration, startup connects to the default local host.

The welcome page selects the last destination you requested, including the
default local host. This choice survives quitting or detaching from Neovim and
restarting Nauvim. An alias outside the configured list is restored under
**Type yourself**. With no saved choice, the default local host is selected.
This selection does not change the automatic startup rules above. See
[host selection storage](docs/persistence.md#host-selection) for its location
and recovery.

Use `j` to move down and `k` to move up, then Enter to select. Up/Down, Tab/Shift-Tab,
and Ctrl-n/Ctrl-p also move between choices. Select **Type yourself** to enter
another host alias; Enter connects and Escape returns to the menu while keeping
the draft. In text entry, `hjkl` types normally. Escape also cancels a pending
connection. In the menu, `q` closes Nauvim and terminates its process.

### Key bindings

Add `key_bindings` to the selected UI options in `nauvim/init.lua`. Omitted
bindings keep their defaults. Each context maps a key chord to an action;
`false` removes that chord's default binding:

```lua
return {
    hosts = { work = {} },
    ui_opts = {
        ["com.naughie.nauvim.flutter"] = {
            key_bindings = {
                welcome = {
                    ["j"] = false,
                    ["Ctrl-n"] = "select_next",
                    ["Ctrl-q"] = "quit",
                },
                clipboard = {
                    ["Alt-c"] = "copy",
                    ["Alt_v"] = "paste",
                },
                webview = {
                    ["Escape"] = "focus_editor",
                    ["Ctrl-r"] = "reload",
                },
            },
        },
    },
}
```

Join modifiers with hyphens or underscores: `Ctrl-Shift-c`, `control_shift_c`,
and `Ctrl-C` name the same chord. Capital letter keys imply Shift: `J` means
`Shift-j`, while `j` remains unmodified. Modifier and named-key spellings are
case-insensitive. Plus signs are not modifier separators.
See the [key binding reference](docs/key-bindings.md) for actions, aliases,
defaults, and context rules. Restart Nauvim after changing the configuration.

## Editing and lifecycle

Editing keys go to Neovim and use its mappings. Nauvim handles only the
configured copy and paste shortcuts.
Paste with Ctrl-Shift-v on Linux or Command-v on
macOS; the engine reads the client clipboard and uses Neovim's paste interface.
Drag text within a grid and copy with Ctrl-Shift-c or Command-c. Selection stays
within that grid. Mouse actions operate GUI controls and never send Neovim mouse
input. Native IME composition is not implemented.

The editor grid uses whole cells in both dimensions. A dedicated one-cell-high
command row sits immediately below it. Showing or clearing command input and
messages does not move the statusline, resize the grid, or change `cmdheight`.

Fonts are tried in configuration order, retaining each face's configured size.
The first available face determines the fixed cell dimensions; fallback glyphs
share its baseline. Normal window resizing uses cell increments. See
[font and grid rendering](docs/fonts-and-grid.md) for metrics and window-manager
constraints.

Prepared fonts persist across launches in a SQLite cache. Source files and
native font preferences are checked on every resolution. Cache failures appear
as diagnostics while fonts continue loading from their source files. See
[font cache storage and recovery](docs/persistence.md#location-and-recovery)
for the location and clearing procedure.

The detach button and Neovim's `:detach` return to the welcome page. Host exit or
connection failure also returns there. Startup selection is not repeated after
detachment. Closing the GUI or receiving SIGTERM waits for engine cleanup and
preserves host Neovim processes for later reattachment.
When Nauvim is the host's only attached UI, it restores a complete initial
display before showing reattached buffers. See
[reattachment troubleshooting](docs/troubleshooting.md#blank-buffers-after-reattachment)
for build and protocol details.

Plugin HTTP previews appear as native WebKit overlays positioned in their
requested grid cells. They retain URL fragments and accept the self-signed
certificates used by core HTTP servers. Navigation failures appear in the
client error display. Attachment transitions close previews and discard pending
presentation work.

## Changing the design

The headless controller, unstyled Flutter components, and default Material design
are separate libraries. Start with [changing the Flutter design](docs/architecture.md)
to replace themes, window sections, or the complete widget tree.

## Development and validation

The [development guide](docs/development.md) explains checks, desktop integration
tests, and bridge regeneration. The [Rust architecture guide](rust/README.md)
explains runtime ownership, snapshot projection, and font processing. See
[font and grid rendering](docs/fonts-and-grid.md) when changing cell geometry.

## Appendix: OpenType font selection

`family` selects the **Typographic Family name** (the OpenType `name` table's
name ID 16). `subfamily`, when present, selects the **Typographic Subfamily name**
(name ID 17). These are the terms defined by the
[OpenType naming-table specification](https://learn.microsoft.com/en-us/typography/opentype/spec/name).
They do not select Font Family/Subfamily names from IDs 1/2, full names, PostScript
names, or filenames. A face without the required typographic-name records does
not match a named request. Matching compares decoded name strings exactly,
including case; it does not normalize or translate the configured string.

The reserved strings `monospace`, `sans-serif`, and `serif`, without `path`, are
system generic selectors. They use the platform's preferred face instead of
comparing the requested family to name ID 16. A supplied `subfamily` still
requires name ID 17.

With `path`, Nauvim reads that file instead of searching installed fonts. Relative
paths are resolved against the canonical configuration file's directory, after
resolving any configuration-file symlink. The family and optional subfamily must
still match a face in the file. Supported resources are
OpenType SFNT fonts (`0x00010000` or `OTTO`), including OpenType collections.
For collections, Nauvim inspects the faces and extracts the selected face for
Flutter. File extension does not determine the font format.

Without `path`, Fontconfig on Linux and CoreText on macOS provide installed-font
candidates. Nauvim checks their OpenType names itself. Linux uses Fontconfig's
preference order. macOS tries its preferred normal face first, followed by the
platform's enumeration order for other exact matches. Within an explicit
collection file, the first matching face in collection order is selected. Use
`subfamily` and `path` when a family has multiple possible matches. Configured
fonts retain their order for grid glyph fallback and their own sizes. A failed
font request produces a diagnostic and is skipped; if none resolve, Nauvim uses
the system monospace font.

Grid fallback checks each face's Unicode `cmap` coverage for a Neovim cell's
code points. Joiners and variation selectors do not disqualify a face during
this check; shaping belongs to Flutter. If none of the configured faces covers
the cell, Flutter's platform glyph fallback remains available.

For a **variable font**, the selected face uses its **default instance**: every
axis takes its `defaultValue` from the `fvar` table. This applies whether
`subfamily` is omitted or matches the face's name ID 17. A named instance's
`InstanceRecord.subfamilyNameID` is a different selector, even though OpenType
calls its value equivalent to a typographic subfamily name. This UI schema does
not use named instances or arbitrary variation coordinates. See the
[OpenType `fvar` specification](https://learn.microsoft.com/en-us/typography/opentype/spec/fvar).

Flutter's family-name lookup alone cannot express strict name-ID matching or a
collection face index. Nauvim therefore selects and inspects faces with Skrifa,
loads each selected face under a private Flutter family alias, and passes the
variable font's default axis coordinates to text rendering. The same face and
instance supply both metrics and glyphs. Neovim's bold and italic highlight
attributes remain Flutter text-style requests on that selected face.
