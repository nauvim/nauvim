# Configure key bindings

Set `key_bindings` inside your selected frontend UI options in
`nauvim/init.lua`. See the [configuration example](../README.md#key-bindings).
The table has three optional contexts: `welcome`, `clipboard`, and `webview`.
Each context maps a key string to an action string or `false`.

## Override and remove bindings

Overrides apply to individual chords. All omitted chords retain their defaults;
an omitted or empty context keeps all of its defaults. Assigning a new chord to
an action adds another shortcut. To move an action, disable the old chord too:

```lua
key_bindings = {
    welcome = {
        ["q"] = false,
        ["Ctrl+Q"] = "quit",
        ["Enter"] = false,
        ["F2"] = "activate",
    },
}
```

This fragment belongs inside the selected UI options table. It retains other
activation bindings, including `NumpadEnter`. `false` removes Nauvim's binding;
it does not disable Neovim, native text editing, or browser shortcuts.

Changes take effect on the next launch. Invalid chords, unknown contexts,
actions in the wrong context, and duplicate normalized chords produce
configuration diagnostics. Like other invalid UI options, they trigger core's
complete-default configuration fallback, including host settings. Two Lua keys
such as `Ctrl+C` and `Control+c` are duplicates within the same context.

## Key strings

A chord consists of zero or more modifiers followed by one logical key, joined
by `+`. This uses the modifier-plus-key style of terminal configurations such as
[kitty](https://sw.kovidgoyal.net/kitty/mapping/). It identifies the logical key
from the active keyboard layout, rather than a physical key position.

Modifier order is free. Names and ASCII letters are case-insensitive, and spaces
around each component are ignored. These strings all mean the same chord:

```text
Ctrl+Shift+C
shift+control+c
 control + SHIFT + c
```

| Modifier | Accepted names |
| --- | --- |
| Control | `Ctrl`, `Control` |
| Shift | `Shift` |
| Alt | `Alt`, `Option`, `Opt` |
| Meta | `Super`, `Meta`, `Command`, `Cmd` |

Meta means Command on macOS and Super on Linux. Modifiers match exactly;
`Ctrl+C` and `Ctrl+Shift+C` are different chords. Caps Lock and Num Lock do not
count as modifiers. Repeating the same modifier through an alias is an error.

ASCII letter case never implies Shift: `j` and `J` name the same unmodified
key, while `Shift+J` names the shifted chord. For shifted punctuation, name its
logical symbol and include Shift explicitly, such as `Shift+Plus`. Letters and
digits keep their key identity across Shift: `Shift+1` names the shifted digit
key, even when it produces `!`. Unicode keys such as `é` or `Ж` are also
accepted and normalized to their uppercase keyboard labels.

The welcome page and editor use Flutter's logical-key identities, including its
Latin shortcut mapping on non-Latin layouts. Native previews resolve keys
through the platform keyboard layout.

| Key | Accepted names |
| --- | --- |
| Escape | `Escape`, `Esc` |
| Enter | `Enter`, `Return` |
| Numeric keypad Enter | `NumpadEnter` |
| Tab | `Tab` |
| Space | `Space` |
| Plus | `Plus` |
| Minus | `Minus`, `-` |
| Backspace | `Backspace`, `BS` |
| Delete | `Delete`, `Del` |
| Insert | `Insert`, `Ins` |
| Arrows | `Up`, `Down`, `Left`, `Right`, or `ArrowUp`, `ArrowDown`, `ArrowLeft`, `ArrowRight` |
| Home and End | `Home`, `End` |
| Page Up | `PageUp`, `PgUp` |
| Page Down | `PageDown`, `PgDown`, `PgDn` |
| Function keys | `F1` through `F24` |

Other printable single Unicode characters name themselves. Use `Plus` for the
plus key and `Space` for a space, so neither can be confused with syntax.
Key sequences, physical scan codes, and Neovim notation such as `<C-c>` are
not part of this grammar.

## Welcome actions

| Action | Behavior | Default keys |
| --- | --- | --- |
| `select_next` | Moves down, wrapping at the end | `j`, `Down`, `Tab`, `Ctrl+N` |
| `select_previous` | Moves up, wrapping at the start | `k`, `Up`, `Shift+Tab`, `Ctrl+P` |
| `activate` | Selects a destination or submits the entered alias | `Enter`, `NumpadEnter`, including modified variants |
| `back` | Leaves text entry or cancels a pending connection | `Escape`, including modified variants |
| `quit` | Closes Nauvim, preserving the host Neovim | `q` |

Navigation and quit bindings operate in the destination menu. In host text
entry they remain ordinary input, so binding `j` or `q` does not prevent typing
those letters in a host name. Activate and back bindings also work in text
entry. The text input's Done action follows the unmodified Enter binding;
disabling it leaves the configured activation chord and the connection button
available. Only navigation repeats while a key is held.

The welcome page shows hints from the effective bindings, including configured
overrides. An action with no remaining bindings is shown as unbound.
Enter and Escape retain their original acceptance of modifier combinations.
Each variant is a separate chord: disabling `Enter` leaves `Ctrl+Enter`, for
example, available unless it is also disabled.

## Clipboard actions

| Action | Behavior | Linux default | macOS default |
| --- | --- | --- | --- |
| `copy` | Copies the grid's selected text to the client clipboard | `Ctrl+Shift+C` | `Super+C` |
| `paste` | Requests the engine's authorized clipboard paste | `Ctrl+Shift+V` | `Super+V` |

These bindings operate while the editor canvas has keyboard focus. Copy falls
through to Neovim when there is no grid selection. Other unbound editor keys
continue to Neovim through the existing key encoder. They do not configure text
fields or web pages' native clipboard behavior.

## Webview actions

Webviews have no Nauvim bindings by default. Configured chords are handled only
while a native preview has keyboard focus; unbound chords retain browser
behavior. They do not intercept editor input.

| Action | Behavior |
| --- | --- |
| `reload` | Reloads the focused preview |
| `go_back` | Navigates backward through its history |
| `go_forward` | Navigates forward through its history |
| `focus_editor` | Returns keyboard focus to the editor |
| `close` | Closes that preview and returns focus to the editor |

Closing a preview leaves its host plugin resource owned by core. A later
explicit plugin open request can show it again. Editor detachment and shutdown
retain the existing preview cleanup behavior.
