# Configure Nauvim

Create `nauvim/init.lua` in the configuration directory of the machine running
the GUI. Use `$XDG_CONFIG_HOME/nauvim/init.lua` when `XDG_CONFIG_HOME` is nonempty.
Otherwise, use `~/.config/nauvim/init.lua` on Linux or
`~/Library/Application Support/nauvim/init.lua` on macOS. To use another file,
start Nauvim with `nauvim --config /absolute/path/init.lua`. Restart Nauvim after
editing the file. If the default file is absent, Nauvim starts with default
values.

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
                startup_size = { width = "100em", height = "720px" },
                margin = { left = 8, right = 8 },
            },
        },
    },
}
```

## Lua modules

Use `require()` in your configuration to load Lua modules. For example,
`require("tools.options")` first searches `lua/tools/options.lua` and then
`lua/tools/options/init.lua` next to the resolved configuration file.

Supply additional Lua filename templates with `--lua-path TEMPLATE` or set
`NAUVIM_LUA_PATH` to a semicolon-separated list of templates. Repeat
`--lua-path` to add more than one template.

```sh
NAUVIM_LUA_PATH='/path/to/shared/?.lua;/path/to/shared/?/init.lua' \
  nauvim --lua-path '/path/to/profile/?.lua'
```

The configuration-relative templates come first, then command-line templates
in argument order, then `NAUVIM_LUA_PATH` entries in order, and then the
existing Lua `package.path`. You can use the added templates from the first
statement of your configuration.

## Hosts and startup

| Configuration | At launch |
| --- | --- |
| No hosts and a table or nil `default_host` | Connect to the independent default host. |
| Hosts and a table or nil `default_host` | Show the welcome page with those aliases and the independent default host. |
| `default_host = "work"` | Connect to `work` automatically. |

Set `default_host` to a table to configure the **Default host** choice. For
example, `default_host = { nvim = "/opt/neovim/bin/nvim" }` selects that local
executable. Include `ssh` and set `ssh.host_name` to configure a remote default.
Omit `default_host` or set it to nil to use the independent local host with any
settings from `hosts_default_params`. With a string alias in `default_host`,
the independent choice uses the built-in local defaults. Aliases named
`local` and `default` are separate choices.

A configured host without `ssh` runs locally. To connect to an SSH alias
outside the list, select **Type yourself** on the welcome page. The welcome
page selects the last requested destination, or **Default host** on first use.
To clear that selection, see [saved destinations](persistence.md#host-selection).

Use `hosts_default_params` to share `nvim`, `socket`, and `policies` settings
across hosts. A host's own value replaces the entire shared field. Set
`ssh = { config = false }` at the top level to resolve SSH destinations from
Nauvim settings and defaults. See the
[core configuration reference](https://github.com/nauvim/nauvim-core/blob/16e53e85d59162335b1e00b17363dd35368dcd90/docs/usage.md)
for all host, SSH, program, socket, and clipboard settings.

### Host plugin permissions

Grant plugin permissions separately under `hosts[alias].policies.plugin` for
an alias or `default_host.policies.plugin` for a configured default host.
Set `hosts_default_params.policies` to share a policy. After host defaults are
applied, an omitted or empty policy grants no permissions. To allow a trusted
host to write to the client clipboard and open web previews for one origin, add
this field to its host entry.

```lua
policies = {
    plugin = {
        clipboard = { copy = true },
        http = { open_webview = { origins = { "https://docs.example.com" } } },
    },
}
```

Nauvim checks the origin when opening the preview and on each top-level
navigation, including redirects. On Linux, the check also applies to
navigations within embedded frames. See the
[host plugin permissions reference](https://github.com/nauvim/nauvim-core/blob/16e53e85d59162335b1e00b17363dd35368dcd90/docs/usage.md#host-plugin-permissions)
for file serving, copying files, and local forwarding.

## Native text input

The focused editor uses the desktop's native text input system by default.
Use your desktop's controls to change the input source, activate an input
method, or change conversion modes. Set the top-level `ime = false` to use
the ordinary Neovim key path.

## UI options

The Flutter UI selects `ui_opts["com.naughie.nauvim.flutter"]` by default.
Lua configuration can read this implementation ID as
`require("nauvim-client-info").ui_id`.
Set the top-level `use_ui_opts = "my-settings"` to select
`ui_opts["my-settings"]` instead. Exactly one dictionary is selected. A
missing entry uses the UI defaults, including when `use_ui_opts` is set.

Each entry is a dictionary with string keys. Values can be booleans, numbers,
strings, lists, or nested dictionaries. Lists use consecutive integer keys
starting at 1. Strings must be valid UTF-8, with no NUL or initial U+FEFF. Keys
in `ui_opts` and the value of `use_ui_opts` must also be nonempty. Core applies
these rules to every dictionary. Nauvim checks the option names and values
below for the selected dictionary. See the
[shared UI configuration rules](https://github.com/nauvim/nauvim-spec/blob/v1.3.0/specification.md#ui-specific-configuration).

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
| `startup_size` | `nil` | Set a windowed size, request a startup mode, or restore the last size. |
| `margin.top`, `margin.bottom`, `margin.left`, `margin.right` | `0` | Nonnegative space around the editor grid and command row. |
| `decorations` | `"full"` | Set to `"none"` for a borderless window. Use your window manager to move or resize it. |
| `opacity` | `1` | Whole-window opacity from `0` (invisible) to `1` (opaque). Linux window opacity requires compositor support. |

- A table such as `startup_size = { width = "100em", height = 720 }` requests
  a windowed client-area size, including toolbars and margins. Each dimension
  must be positive when set. Omit either dimension to use the platform's default
  for that axis. An empty table uses platform defaults for both axes.
- Set `startup_size` to `"maximized"` (native zoom on macOS) or `"fullscreen"`
  to request that state before the window appears.
- Omit `startup_size` or set it to `nil` to restore the last saved client-area
  size in windowed mode. Before a size has been saved, Nauvim uses the
  platform's initial size. See [saved window size](persistence.md#window-size).

Use an integer like `720` or a string like `"720px"` to count logical pixels.
Use decimal digits before `px`. An `em` string counts measured cells along the
corresponding axis. For example, `width = "100em"` uses 100 cell widths and
`margin = { top = "0.5em" }` adds half a cell height.

The platform can adjust the requested size or mode. A normal window can snap to
whole-cell increments. Margins apply in all modes.

### Key bindings

Use `key_bindings` to override specific shortcuts on the welcome page, in
the editor, or in a web preview. See the
[complete Linux defaults and key binding reference](key-bindings.md#linux-defaults).

## Configuration fallback

Nauvim treats unknown dictionary keys and values of unsupported types as
omitted. This applies to host settings and to the selected UI options. If
recovery removes a required field without a default, Nauvim drops its containing
dictionary. Nauvim reports other loading or validation failures and uses
defaults for the entire configuration, including hosts. It skips unresolved
fonts individually.
See [configuration troubleshooting](troubleshooting.md#configuration-errors).
