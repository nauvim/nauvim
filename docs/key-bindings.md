# Configure key bindings

## Override and remove bindings

Inside the selected UI entry in `nauvim/init.lua`.
[Full configuration example](configuration.md#full-example)

```lua
key_bindings = {
    welcome = { q = false, ["Ctrl-q"] = "quit" }, -- Move quit from q to Ctrl-q.
    clipboard = { ["Alt-c"] = "copy", ["Alt-v"] = "paste" },
    webview = { ["Alt-Left"] = "go_back", ["Alt-Right"] = "go_forward" },
},
```

Use `false` to remove a binding. Omitted chords keep their defaults.
[Actions and defaults](#actions-and-defaults)

Invalid chords, actions outside their context, and equivalent chords such as
`Ctrl-c` and `Control_c` in one context trigger [configuration fallback](configuration.md#configuration-fallback).

## Key strings

```lua
welcome = {
    ["Ctrl-Page_Down"] = "select_next",
    ["Shift-Plus"] = "select_previous",
    ["Ctrl-C"] = "select_previous", -- Uppercase letters add Shift.
},
```

Join modifiers and the key with `-` or `_`. Modifiers and named keys are
case-insensitive. List each modifier once, in any order.

| Modifier | Accepted names |
| --- | --- |
| Control | `Ctrl`, `Control` |
| Shift | `Shift` |
| Alt | `Alt`, `Option`, `Opt` |
| Command on macOS, Super on Linux | `Super`, `Meta`, `Command`, `Cmd` |

Modifiers match exactly, ignoring Caps Lock and Num Lock. Spell out `Shift`
for named keys such as `Enter` or `F2`.

| Key | Accepted names |
| --- | --- |
| Escape | `Escape`, `Esc` |
| Enter | `Enter`, `Return` |
| Numeric keypad Enter | `NumpadEnter` |
| Tab | `Tab` |
| Space | `Space` |
| Plus | `Plus` |
| Minus | `Minus` |
| Underscore | `Underscore` |
| Backspace | `Backspace`, `BS` |
| Delete | `Delete`, `Del` |
| Insert | `Insert`, `Ins` |
| Arrows | `Up`, `Down`, `Left`, `Right`, or `ArrowUp`, `ArrowDown`, `ArrowLeft`, `ArrowRight` |
| Home and End | `Home`, `End` |
| Page Up | `PageUp`, `PgUp` |
| Page Down | `PageDown`, `PgDown`, `PgDn` |
| Function keys | `F1` through `F24` |

Printable characters name themselves, as in `Ctrl-+`. Use `Minus` and
`Underscore` after modifiers.

<a id="linux-defaults"></a>

## Actions and defaults

### Welcome actions

```lua
welcome = {
    q = false,
    ["Ctrl-q"] = "quit",
},
```

| Action | Behavior | Default keys |
| --- | --- | --- |
| `select_next` | Moves down, wrapping at the end | `j`, `Down`, `Tab`, `Ctrl-n` |
| `select_previous` | Moves up, wrapping at the start | `k`, `Up`, `Shift-Tab`, `Ctrl-p` |
| `activate` | Connects to the selected or typed destination | `Enter`, `NumpadEnter`, with any combination of modifiers |
| `back` | Leaves text entry or cancels a pending connection | `Esc`, with any combination of modifiers |
| `quit` | Closes Nauvim, preserving the host Neovim | `q` |

**Done** in the text field uses the plain `Enter` binding. Each modifier
combination has its own binding.

### Clipboard actions

```lua
clipboard = {
    ["Alt-c"] = "copy",
    ["Alt-v"] = "paste",
},
```

| Action | Behavior | Linux default | macOS default |
| --- | --- | --- | --- |
| `copy` | Copies the grid's selected text to the client clipboard | `Ctrl-Shift-c` | `Super-c` |
| `paste` | Pastes the client clipboard into Neovim | `Ctrl-Shift-v` | `Super-v` |

Applies with editor focus. With no selection, the copy chord goes to Neovim.

### Webview actions

```lua
webview = {
    ["Alt-Left"] = "go_back",
    ["Alt-Right"] = "go_forward",
},
```

| Action | Behavior | Default keys |
| --- | --- | --- |
| `reload` | Reloads the focused preview | `Ctrl-r` |
| `go_back` | Navigates backward through its history | None |
| `go_forward` | Navigates forward through its history | None |
| `focus_editor` | Returns keyboard focus to the editor | `Esc` |
| `close` | Closes that preview and returns focus to the editor | `Ctrl-w` |

Applies with preview focus. Unbound chords keep the browser's behavior.
`focusable = false` disables focus for a preview. `close_on_blur = true`
closes it when focus leaves.

Inspect a preview via **Inspect Element** on Linux or Safari's **Develop**
menu on macOS 13.3 or later.
[WebKit Inspector documentation](https://webkit.org/blog/13936/enabling-the-inspection-of-web-content-in-apps/)
