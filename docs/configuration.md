# Configure Nauvim

Create `nauvim/init.lua` in the configuration directory of the machine running
the GUI. Use `$XDG_CONFIG_HOME/nauvim/init.lua` when `XDG_CONFIG_HOME` is nonempty.
Otherwise, use `~/.config/nauvim/init.lua` on Linux or
`~/Library/Application Support/nauvim/init.lua` on macOS. To use another file,
start Nauvim with `nauvim --config /absolute/path/init.lua`. Restart Nauvim after
editing the file.

```lua
return {
    hosts = {
        laptop = {},
        work = { ssh = { host_name = "work.example.com" } },
    },
    ui_opts = {
        ["com.naughie.nauvim.flutter"] = {
            fonts = { family = "monospace", size = 14 },
            window = {
                width = "100em",
                height = "720px",
                margin = { left = 8, right = 8 },
            },
            key_bindings = {
                welcome = { ["Ctrl-q"] = "quit" },
            },
        },
    },
}
```

## Hosts and startup

| Configuration | At launch |
| --- | --- |
| No hosts and no `default_host` | Connect to the default local host. |
| Hosts and no `default_host` | Show the welcome page with those aliases and the default local host. |
| `default_host = "work"` | Connect to `work` automatically. |

A configured host without `ssh` runs locally. To connect to an SSH alias
outside the list, select **Type yourself** on the welcome page. The separate
default local choice uses the default program and socket settings, even when
you configure an alias named `local` or `default`.

When the welcome page opens, it selects the last requested destination, or the
default local host on first use. To clear that selection, see
[saved destinations](persistence.md#host-selection).

For Neovim arguments, socket paths, SSH settings, clipboard backends, host
policies, and loading Lua modules, see the
[core configuration reference](https://github.com/nauvim/nauvim-core/blob/327333378cca69070fdbffcffa65509d9d2b4d7d/docs/usage.md).

## UI options

The Flutter UI selects `ui_opts["com.naughie.nauvim.flutter"]` by default.
Set the top-level `use_ui_opts = "my-settings"` to select
`ui_opts["my-settings"]` instead. Exactly one dictionary is selected. A
missing entry uses the UI defaults, including when `use_ui_opts` is set.

Each entry is a dictionary with string keys. Values can be booleans, numbers,
strings, lists, or nested dictionaries. Lists use consecutive integer keys
starting at 1. Strings must be valid UTF-8, with no NUL or initial U+FEFF. Keys
in `ui_opts` and the value of `use_ui_opts` must also be nonempty. Core applies
these rules to every dictionary. Nauvim checks the option names and values
below for the selected dictionary. See the
[shared UI configuration rules](https://github.com/nauvim/nauvim-spec/blob/9913ab5c25816a870561c4badb475f5b5ccf4693/specification.md#810-ui-specific-configuration).

### Fonts

Set `fonts` to a family string, a table, or an ordered list of tables. For
example, `fonts = "monospace"` selects the system monospace face at the default
size of 15 logical pixels.

| Field | Value |
| --- | --- |
| `family` | The exact OpenType Typographic Family name (name ID 16). Without a `path`, `monospace`, `sans-serif`, and `serif` select the system's preferred faces for those families. |
| `subfamily` | Optional exact Typographic Subfamily name (name ID 17), also applied to system selectors. |
| `size` | Positive integer in logical pixels. The default is 15. |
| `path` | Optional path to an OpenType font or collection. Relative paths resolve against the configuration file's directory after following symlinks. The first face in the file that matches the given names is used. |

Font names are case-sensitive and nonempty. With `path`, the family is always
taken literally. Variable fonts use their default instance. The first usable font
sets the editor's cell size. Later fonts provide fallback glyphs at their
configured sizes. Nauvim reports unavailable fonts and uses system monospace
if the list is empty or none resolve.

### Window

| Field | Default | Effect |
| --- | --- | --- |
| `width`, `height` | Platform's initial size | Positive initial client-area size, including toolbar and margins. |
| `margin.top`, `margin.bottom`, `margin.left`, `margin.right` | `0` | Nonnegative space around the editor grid and command row. |
| `decorations` | `"full"` | Set to `"none"` for a borderless window. Use your window manager to move or resize it. |
| `opacity` | `1` | Whole-window opacity from `0` (invisible) to `1` (opaque). Linux window opacity requires compositor support. |
| `startup_mode` | `"windowed"` | Set to `"maximized"` (native zoom on macOS) or `"fullscreen"` to request that state before the window appears. |

An integer like `720` or a string like `"720px"` counts logical pixels.
Use decimal digits before `px`.
Use an `em` string for cell-relative lengths. For example, `width = "100em"`
uses 100 measured cell widths, and `margin = { top = "0.5em" }` adds half a
measured cell height. The available editor space depends on the margins and
other controls inside the window.

Nauvim resolves these settings once at startup. The platform can adjust the
requested window size or mode. A normal window can snap to whole-cell
increments. Margins apply in all modes.

### Key bindings

Use `key_bindings` to override specific shortcuts on the welcome page, in
the editor, or in a web preview. See the [key binding reference](key-bindings.md).

## Configuration fallback

If Lua cannot load the file, a dictionary breaks the shared UI option rules, or
the selected options fail validation, Nauvim reports the error and uses defaults
for the entire configuration, including hosts. An unresolved font is skipped
individually. See [configuration troubleshooting](troubleshooting.md#configuration-errors).
