# Configure Nauvim

## Full example

Save as [`nauvim/init.lua`](#configuration-file-location) on the GUI machine.
Edit `hosts.work` before connecting to it. [SSH settings](#ssh)

```lua
local client = require("nauvim-client-info")

return {
    -- Use "work" to connect on launch or a host table to configure Default host.
    default_host = nil, -- With hosts below, show the welcome page.
    hosts_default_params = {
        nvim = "nvim", -- Shared defaults for nvim, socket, and policies.
    },
    hosts = {
        laptop = {}, -- Runs locally with the shared Neovim setting.
        work = {
            nvim = {
                prog = "/usr/bin/nvim", -- Executable on the SSH host.
                args = { "-O2" },
                env = { NVIM_APPNAME = "work-nvim" }, -- Use a separate Neovim profile.
            },
            socket = nil, -- Or "/tmp/my-nauvim-work.sock" on the host.
            ssh = {
                host_name = "work.example.com",
                user = "dev",
                port = 22,
                -- identity_file = client.home_dir .. "/.ssh/work_ed25519",
            },
            policies = {
                plugin = {
                    clipboard = { copy = false }, -- Enable for a trusted host.
                    http = { open_webview = { origins = { "https://docs.example.com" } } },
                },
            },
        },
    },
    ssh = {
        config = client.home_dir .. "/.ssh/config", -- OpenSSH settings on the client.
        -- config = false, -- Resolve SSH destinations from Nauvim settings.
        known_hosts = client.home_dir .. "/.ssh/known_hosts",
    },
    clipboard = {
        backend = "auto", -- Or "wl_clipboard", "xclip", "xsel", or "pbcopy".
        timeout_ms = 3000,
    },
    ime = true, -- Use native text input. Set false for ordinary Neovim key input.
    use_ui_opts = nil, -- Use the UI ID below, or name another entry in ui_opts.
    ui_opts = {
        ["com.naughie.nauvim.flutter"] = {
            fonts = { -- A family string, one font table, or a list in fallback order.
                { family = "monospace", size = 15 },
                { family = "sans-serif", size = 15 },
            },
            window = {
                -- Or use "maximized", "fullscreen", or nil (restore the saved size).
                startup_size = { width = "100em", height = "720px" },
                margin = { top = "0.5em", bottom = 0, left = 8, right = 8 },
                decorations = "full", -- Use "none" for a borderless window.
                opacity = 1, -- 0 is invisible and 1 is opaque.
            },
            key_bindings = { -- Omit a chord to keep its default. Use false to remove it.
                welcome = { q = false, ["Ctrl-q"] = "quit" },
                clipboard = { ["Alt-c"] = "copy", ["Alt-v"] = "paste" },
                webview = { ["Alt-Left"] = "go_back", ["Alt-Right"] = "go_forward" },
            },
        },
    },
}
```

## Configuration file location

| Environment | Path |
| --- | --- |
| Nonempty `XDG_CONFIG_HOME` | `$XDG_CONFIG_HOME/nauvim/init.lua` |
| Linux | `~/.config/nauvim/init.lua` |
| macOS | `~/Library/Application Support/nauvim/init.lua` |

To use another file, start Nauvim with its path.

```sh
nauvim --config /absolute/path/init.lua
```

Restart after edits. Nauvim uses built-in settings if the default file is absent.

## Hosts and startup

```lua
default_host = nil,
-- default_host = "work", -- Connect on launch.
-- default_host = { nvim = "/opt/neovim/bin/nvim" }, -- Local Default host.
hosts = {
    laptop = {}, -- Local. Aliases are case-sensitive.
    work = { ssh = { host_name = "work.example.com" } },
},
```

| `default_host` | Startup | **Default host** |
| --- | --- | --- |
| `nil` or omitted | Welcome page with named hosts, or connect to **Default host** when `hosts` is empty | Local, with shared settings |
| Host table | Same as `nil` | Uses the table. Set `ssh.host_name` for SSH. |
| Alias string, e.g. `"work"` | Connect to that alias | Built-in local settings |

For an unlisted SSH destination, choose **Type yourself**. [Saved destinations](persistence.md#host-selection)

### Shared host settings

```lua
hosts_default_params = {
    nvim = { prog = "nvim", args = { "-O2" } },
    policies = {},
},
hosts = {
    laptop = {}, -- Inherits nvim, including "-O2".
    work = {
        nvim = { prog = "/usr/bin/nvim" }, -- Replaces the whole nvim table.
        ssh = { host_name = "work.example.com" },
    },
},
```

Named hosts and **Default host** (table or `nil`) inherit omitted or `nil`
`nvim`, `socket`, and `policies` fields. Use `policies = {}` on a host to clear
its inherited permissions.

### Neovim program and socket

Inside `hosts.work` or a `default_host` table.

```lua
nvim = {
    prog = "/usr/bin/nvim", -- Defaults to "nvim" on the host's PATH.
    args = { "-O2" }, -- Literal arguments.
    env = { NVIM_APPNAME = "work-nvim" }, -- Overrides inherited values.
},
-- nvim = "/usr/bin/nvim", -- Executable with no extra arguments.
-- nvim = function(host) return host.home_dir .. "/bin/nvim" end,
socket = "/tmp/my-nauvim-work.sock", -- Omit to use a generated path.
```

| Detail | Behavior |
| --- | --- |
| Launch | Appends `--headless --listen <socket>` and sets `NAUVIM_CONNECTION` to `local` or `ssh`. Wrappers pass both through. |
| Socket | Reuses a session at the selected path. The default is a per-destination path under `/tmp/nauvim-sockets-<uid>` on the host. |
| Function value | `nvim` and `socket` functions run on the client with the target's host information. |

### SSH

```lua
hosts = {
    work = {
        ssh = { -- Settings for this destination.
            host_name = "work.example.com", -- Defaults to the alias.
            user = "dev", -- Defaults to your local username.
            port = 22,
            identity_file = "/home/me/.ssh/work_ed25519",
            -- certificate_file = "/home/me/.ssh/work_ed25519-cert.pub",
            -- identity_agent = os.getenv("SSH_AUTH_SOCK"),
            -- identities_only = true,
            -- proxy_jump = "bastion",
            -- kex_algorithms = { "curve25519-sha256" },
            -- host_key_algorithms = { "ssh-ed25519" },
        },
    },
},
ssh = { -- Files on the GUI machine.
    config = "/home/me/.ssh/config", -- Defaults to ~/.ssh/config.
    -- config = { path = "/home/me/.ssh/config", format = "openssh" },
    -- config = false, -- Also accepts { disabled = true }.
    known_hosts = "/home/me/.ssh/known_hosts", -- Defaults to ~/.ssh/known_hosts.
},
```

| Detail | Rule |
| --- | --- |
| Lookup order | Host entry → named SSH entry for `host_name` → OpenSSH file if enabled → built-in defaults |
| `ssh.config` | Use a readable file, or `false` to skip OpenSSH lookup. Formats `"openssh"` and `"auto"` both read OpenSSH. |
| `ssh.known_hosts` | Trust file for the destination and jump hosts, even with `config = false`. |
| Paths and agent | Use absolute client paths. Set `identity_agent` explicitly to use `SSH_AUTH_SOCK`. |
| `identities_only` | Boolean or `"yes"`, `"no"`, `"true"`, `"false"` |
| `proxy_jump` | Alias, `{ host_name = "bastion.example.com" }`, or a list of either |
| Algorithm lists | Lua list or comma-separated string. Prefix with `+`, `-`, or `^` to append, remove, or prepend. List certificate algorithms before plain host keys. |

An unlisted alias uses OpenSSH settings when enabled. With `config = false`,
the alias is the hostname.

### Host plugin permissions

In a trusted host's entry or in `hosts_default_params`.

```lua
policies = {
    plugin = {
        clipboard = { copy = true },
        filesystem = { copy = true },
        http = {
            serve_file = true,
            open_webview = {
                origins = { "https://docs.example.com" },
                served_files = true,
            },
        },
        local_forward = {
            tcp = { { client_port = 0, host_addr = "localhost", host_port = 8080 } },
            socket = {
                { client_socket_path = "preview.sock", host_socket_path = "/run/preview.sock" },
            },
        },
    },
},
```

| Permission | Allows |
| --- | --- |
| `clipboard.copy` | Write to the client clipboard |
| `filesystem.copy` | Copy to the client's Nauvim temporary directory |
| `http.serve_file` | Serve files from that directory |
| `http.open_webview.origins` | Preview origins by scheme, host, and effective port |
| `http.open_webview.served_files` | Preview the attachment's own file servers |
| `local_forward.tcp` | Match all three endpoint fields. Port `0` chooses a free client port. |
| `local_forward.socket` | Match a client path relative to the temporary directory and an absolute host path. |

Empty effective policies grant no permissions. The origin, TCP, and socket
lists each accept `"all"`. Nauvim checks origins on open and top-level
navigation, including redirects. Linux also checks embedded frames.

## Clipboard

```lua
clipboard = {
    backend = "auto",
    timeout_ms = 3000, -- Positive integer in milliseconds.
},
-- clipboard = "wl_clipboard", -- Backend with the default timeout.
```

| Backend | Client commands |
| --- | --- |
| `"auto"` | Default. Tries Wayland, then X11 on Linux. Uses `pbcopy` and `pbpaste` on macOS. |
| `"wl_clipboard"` | `wl-copy` and `wl-paste` on Wayland |
| `"xclip"` | `xclip` on X11 |
| `"xsel"` | `xsel` on X11 |
| `"pbcopy"` | `pbcopy` and `pbpaste` on macOS |

An invalid timeout uses 3000 ms. If the backend is unavailable, ordinary
editing still works. [Runtime prerequisites](building.md#runtime-prerequisites)

## Native text input

```lua
ime = true, -- Default. Use the desktop's native input method.
-- ime = false, -- Use ordinary Neovim key input.
```

Use your desktop controls to change input sources or conversion modes.

## UI options

```lua
use_ui_opts = "compact", -- Omit for the com.naughie.nauvim.flutter entry.
ui_opts = {
    ["com.naughie.nauvim.flutter"] = { fonts = "monospace" },
    compact = { fonts = { family = "monospace", size = 12 } },
},
```

Nauvim selects one entry. A missing entry uses the built-in UI defaults.

### Fonts

Inside the selected UI entry.

```lua
fonts = {
    { family = "monospace", size = 15 }, -- Primary font.
    { family = "sans-serif", size = 15 }, -- First fallback.
},
-- fonts = "monospace",
-- fonts = { family = "monospace", size = 17 },
```

For a font file, use the names in that file.

```lua
fonts = {
    family = "Example Mono",
    subfamily = "Regular",
    size = 16,
    path = "fonts/ExampleMono-Regular.otf",
},
```

| Field | Values and defaults |
| --- | --- |
| `family` | Exact OpenType Typographic Family (ID 16). Omit `path` to use system selectors `monospace`, `sans-serif`, or `serif`. |
| `subfamily` | Optional exact OpenType Typographic Subfamily (ID 17) |
| `size` | Positive integer in logical pixels. Default `15`. |
| `path` | Optional OpenType file or collection. Uses the first matching face. Relative to the resolved `init.lua` directory. |

Names are case-sensitive. The first usable font sets cell size. An empty
or unusable list falls back to system monospace.

### Window

Inside the selected UI entry. Choose one `startup_size` line.

```lua
window = {
    startup_size = { width = "100em", height = "720px" }, -- 100 cells wide, 720 px tall.
    -- startup_size = "maximized",
    -- startup_size = "fullscreen",
    -- startup_size = nil, -- Restore the saved windowed size.
    margin = { top = "0.5em", bottom = 0, left = 8, right = 8 },
    decorations = "full", -- Or "none".
    opacity = 1, -- Try 0.9 for a translucent window.
},
```

| Field | Value | Behavior |
| --- | --- | --- |
| `startup_size` | `nil` (default) | Restore saved size, or use the platform default if none is saved. |
| | `{ width = ..., height = ... }` | Set the client area including toolbars and margins. Omitted axes use platform defaults. |
| | `"maximized"` | Maximize on launch (native zoom on macOS). |
| | `"fullscreen"` | Enter fullscreen on launch. |
| `margin` | `top`, `bottom`, `left`, `right` | Nonnegative space around the editor and command row in every mode. Default `0` per side. |
| `decorations` | `"full"` (default), `"none"` | With `"none"`, move and resize the borderless window through the window manager. |
| `opacity` | `0` to `1` (default `1`) | Invisible to opaque. On Linux, requires compositor support. |

Use whole logical pixels (`720` or `"720px"`) or cells (`"0.5em"`). Startup
dimensions must be positive. The platform can adjust the requested size or
mode and snap a windowed size to whole cells. [Saved window size](persistence.md#window-size)

### Key bindings

Inside the selected UI entry.

```lua
key_bindings = {
    welcome = { q = false, ["Ctrl-q"] = "quit" }, -- Omitted chords keep defaults.
    clipboard = { ["Alt-c"] = "copy", ["Alt-v"] = "paste" },
    webview = { ["Alt-Left"] = "go_back", ["Alt-Right"] = "go_forward" },
},
```

[Key names, actions, and defaults](key-bindings.md)

## Lua modules

Save as `lua/nauvim_fonts.lua` next to `init.lua`.

```lua
return { family = "monospace", size = 15 }
```

Load it from `init.lua`.

```lua
local client = require("nauvim-client-info")
local font = require("nauvim_fonts")
-- font.path = client.home_dir .. "/fonts/MyMono-Regular.otf"

return {
    ui_opts = {
        [client.ui_id] = { fonts = font },
    },
}
```

Add search paths at launch.

```sh
NAUVIM_LUA_PATH='/path/to/shared/?.lua;/path/to/shared/?/init.lua' \
  nauvim --lua-path '/path/to/profile/?.lua'
```

| Search order | Templates |
| --- | --- |
| 1. Resolved `init.lua` directory | `lua/?.lua`, then `lua/?/init.lua` |
| 2. CLI | Repeat `--lua-path` once per template. |
| 3. Environment | Separate `NAUVIM_LUA_PATH` entries with `;`. |
| 4. Lua defaults | Existing `package.path` |

Nauvim runs this file in its own Lua 5.4 interpreter on the client.

## Configuration fallback

| Problem | Result |
| --- | --- |
| Unknown dictionary key or unsupported value type | Treat as omitted. |
| Recovery removes a required field with no default | Drop its dictionary. |
| Other loading or validation error | Report it and use defaults for the entire configuration, including hosts. |
| Unavailable font | Report it and skip that font. |

[Troubleshoot configuration](troubleshooting.md#configuration-errors)

## Further reference

- [Engine configuration reference](https://github.com/nauvim/nauvim-core/blob/16e53e85d59162335b1e00b17363dd35368dcd90/docs/usage.md)
- [Nauvim specification v1.3.0](https://github.com/nauvim/nauvim-spec/blob/v1.3.0/specification.md#configuration)
