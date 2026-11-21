# Configure key bindings

Set `key_bindings` inside the selected UI options in `nauvim/init.lua`.
Use `welcome` for the destination screen, `clipboard` for the editor,
and `webview` for native previews.

## Linux defaults

```lua
key_bindings = {
    welcome = {
        j = "select_next",
        Down = "select_next",
        ["Ctrl-n"] = "select_next",
        Tab = "select_next",
        k = "select_previous",
        Up = "select_previous",
        ["Ctrl-p"] = "select_previous",
        ["Shift-Tab"] = "select_previous",
        q = "quit",

        Enter = "activate",
        ["Ctrl-Enter"] = "activate",
        ["Shift-Enter"] = "activate",
        ["Ctrl-Shift-Enter"] = "activate",
        ["Alt-Enter"] = "activate",
        ["Ctrl-Alt-Enter"] = "activate",
        ["Shift-Alt-Enter"] = "activate",
        ["Ctrl-Shift-Alt-Enter"] = "activate",
        ["Super-Enter"] = "activate",
        ["Ctrl-Super-Enter"] = "activate",
        ["Shift-Super-Enter"] = "activate",
        ["Ctrl-Shift-Super-Enter"] = "activate",
        ["Alt-Super-Enter"] = "activate",
        ["Ctrl-Alt-Super-Enter"] = "activate",
        ["Shift-Alt-Super-Enter"] = "activate",
        ["Ctrl-Shift-Alt-Super-Enter"] = "activate",

        NumpadEnter = "activate",
        ["Ctrl-NumpadEnter"] = "activate",
        ["Shift-NumpadEnter"] = "activate",
        ["Ctrl-Shift-NumpadEnter"] = "activate",
        ["Alt-NumpadEnter"] = "activate",
        ["Ctrl-Alt-NumpadEnter"] = "activate",
        ["Shift-Alt-NumpadEnter"] = "activate",
        ["Ctrl-Shift-Alt-NumpadEnter"] = "activate",
        ["Super-NumpadEnter"] = "activate",
        ["Ctrl-Super-NumpadEnter"] = "activate",
        ["Shift-Super-NumpadEnter"] = "activate",
        ["Ctrl-Shift-Super-NumpadEnter"] = "activate",
        ["Alt-Super-NumpadEnter"] = "activate",
        ["Ctrl-Alt-Super-NumpadEnter"] = "activate",
        ["Shift-Alt-Super-NumpadEnter"] = "activate",
        ["Ctrl-Shift-Alt-Super-NumpadEnter"] = "activate",

        Esc = "back",
        ["Ctrl-Esc"] = "back",
        ["Shift-Esc"] = "back",
        ["Ctrl-Shift-Esc"] = "back",
        ["Alt-Esc"] = "back",
        ["Ctrl-Alt-Esc"] = "back",
        ["Shift-Alt-Esc"] = "back",
        ["Ctrl-Shift-Alt-Esc"] = "back",
        ["Super-Esc"] = "back",
        ["Ctrl-Super-Esc"] = "back",
        ["Shift-Super-Esc"] = "back",
        ["Ctrl-Shift-Super-Esc"] = "back",
        ["Alt-Super-Esc"] = "back",
        ["Ctrl-Alt-Super-Esc"] = "back",
        ["Shift-Alt-Super-Esc"] = "back",
        ["Ctrl-Shift-Alt-Super-Esc"] = "back",
    },
    clipboard = {
        ["Ctrl-Shift-c"] = "copy",
        ["Ctrl-Shift-v"] = "paste",
    },
    webview = {
        ["Ctrl-r"] = "reload",
        ["Ctrl-w"] = "close",
        Esc = "focus_editor",
    },
}
```

## Override and remove bindings

Each context maps a key chord to an action or to `false` to remove the binding
for that chord. Omitted chords retain their defaults. This example adds
`Ctrl-q` for quitting and removes the default `q`.

```lua
key_bindings = {
    welcome = {
        q = false,
        ["Ctrl-q"] = "quit",
    },
}
```

Restart Nauvim after editing the file. Unknown contexts, invalid chords,
actions outside their context, and equivalent chords such as `Ctrl-c` and
`Control_c` in the same context trigger configuration fallback.
[Configuration fallback](configuration.md#configuration-fallback)

## Key strings

A chord names one logical key, optionally preceded by modifiers. Join the
components with `-` or `_`. Modifier and named-key names are case-insensitive.
You can put modifiers in any order and add spaces around components. Each
explicit modifier can appear once.

| Modifier | Accepted names |
| --- | --- |
| Control | `Ctrl`, `Control` |
| Shift | `Shift` |
| Alt | `Alt`, `Option`, `Opt` |
| Meta | `Super`, `Meta`, `Command`, `Cmd` |

Meta means Command on macOS and Super on Linux. Modifiers match exactly,
ignoring Caps Lock and Num Lock. Capital letter keys imply Shift, so `Ctrl-C`
means `Ctrl-Shift-c`, while `Ctrl-c` uses Control without Shift. This also
applies to Unicode letters. For named keys such as `ENTER` or `F2`, spell out
Shift.

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

Other printable single characters name themselves. Use `Minus` and
`Underscore` after modifiers. A literal `+` names the plus key, as in
`Ctrl-+`. Use `Shift-1` for the shifted digit key and `Shift-Plus` for the
shifted plus key. Named keys can include separators, as in `Ctrl-Page_Down`.

## Welcome actions

| Action | Behavior | Default keys |
| --- | --- | --- |
| `select_next` | Moves down, wrapping at the end | `j`, `Down`, `Tab`, `Ctrl-n` |
| `select_previous` | Moves up, wrapping at the start | `k`, `Up`, `Shift-Tab`, `Ctrl-p` |
| `activate` | Selects a destination or submits the entered alias | `Enter`, `NumpadEnter`, including modified variants |
| `back` | Leaves text entry or cancels a pending connection | `Escape`, including modified variants |
| `quit` | Closes Nauvim, preserving the host Neovim | `q` |

Navigation and quit apply in the destination menu. Activate and back also work
while entering an alias. The text field's **Done** action follows the unmodified
Enter binding. Each modifier combination has its own binding, so removing
`Enter` leaves `Ctrl-Enter` available.

## Clipboard actions

| Action | Behavior | Linux default | macOS default |
| --- | --- | --- | --- |
| `copy` | Copies the grid's selected text to the client clipboard | `Ctrl-Shift-c` | `Super-c` |
| `paste` | Pastes the client clipboard into Neovim if host policy allows it | `Ctrl-Shift-v` | `Super-v` |

These bindings apply while the editor has keyboard focus. When there is no
grid selection, the copy chord goes to Neovim.

## Webview actions

These bindings apply while a native preview has keyboard focus. Unbound
chords retain the browser's behavior.

| Action | Behavior | Default keys |
| --- | --- | --- |
| `reload` | Reloads the focused preview | `Ctrl-r` |
| `go_back` | Navigates backward through its history | None |
| `go_forward` | Navigates forward through its history | None |
| `focus_editor` | Returns keyboard focus to the editor | `Esc` |
| `close` | Closes that preview and returns focus to the editor | `Ctrl-w` |

The host plugin can show a closed preview again.
