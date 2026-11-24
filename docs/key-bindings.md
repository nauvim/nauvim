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

Restart Nauvim after editing the file. Nauvim ignores unknown contexts and
binding values of unsupported types. Invalid chords, actions outside their
context, and equivalent chords such as `Ctrl-c` and `Control_c` in the same
context trigger configuration fallback.
[Configuration fallback](configuration.md#configuration-fallback)

## Key strings

A chord matches a key press by its *logical key* and active modifiers. The
logical key is the identity Nauvim obtains from the keyboard event after the
active layout and any remapping have taken effect. The same physical position
can give `a` on a US QWERTY layout and `q` on a French AZERTY layout. Text entry
is separate from shortcut matching. For example, Shift with `1` on a US layout
can enter `!`, while the shortcut is `Shift-1`.

Write the modifiers before the key and join the components with `-` or `_`.
Modifier and named-key names are case-insensitive. You can put modifiers in any
order and add spaces around components. Each explicit modifier can appear once.

| Modifier | Accepted names |
| --- | --- |
| Control | `Ctrl`, `Control` |
| Shift | `Shift` |
| Alt | `Alt`, `Option`, `Opt` |
| Meta | `Super`, `Meta`, `Command`, `Cmd` |

Meta means Command on macOS and Super on Linux. Modifiers match exactly. Include
every modifier from the table that Nauvim sees as active for the key press.
Caps Lock and Num Lock add no modifier to the chord. Capital letter keys imply
Shift, so `Ctrl-C` means `Ctrl-Shift-c`, while `Ctrl-c` uses Control without
Shift. This also applies to Unicode letters. For named keys such as `ENTER` or
`F2`, spell out Shift.

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

For any other printable key identity, use its single character. Use `Minus`
and `Underscore` after modifiers. A literal `+` names the plus key, as in
`Ctrl-+`. Use `Shift-Plus` for a plus key event with Shift active. Named keys
can include separators, as in `Ctrl-Page_Down`.

### Choose a chord for a remapped key

For each gesture you want to bind, check which key reaches the matching
context and which modifiers are active at that moment. If pressing Caps Lock
produces Escape with no active modifiers, use `Escape`. The same rule applies
to remaps from Karabiner-Elements on macOS, `xmodmap` under X11, `xremap` on
Linux, and custom QMK firmware. See the
[Karabiner-Elements EventViewer guide](https://karabiner-elements.pqrs.org/docs/manual/operation/eventviewer/),
the [`xmodmap` manual](https://xorg.freedesktop.org/archive/X11R7.5/doc/man/man1/xmodmap.1.html),
and the [`xremap` documentation](https://github.com/xremap/xremap).

- **Tap and hold.** A key can send Escape when tapped and hold Control and Shift
  when held. The tap matches `Escape` with no active modifiers. If you hold the
  key and Nauvim receives `c` with Control and Shift active, use `Ctrl-Shift-c`.
  See [QMK Mod-Tap](https://docs.qmk.fm/mod_tap).
- **Firmware layers.** A key can send Space when tapped and switch to a
  navigation layer when held. Use `Space` for the unmodified tap. If pressing
  the usual `h` key on that layer sends Left Arrow, use `Left` when the layer
  switch stays inside the firmware and no modifiers reach Nauvim. Use `Alt-Left`
  if the firmware also holds Alt and Nauvim receives it with the arrow event.
  See [QMK layers](https://docs.qmk.fm/feature_layers).

If a macro sends `Alt-Left` and then `Ctrl-r`, each press can match its own
binding in the context that receives it. A single `key_bindings` entry matches
one chord. Try the chord with the target context focused and your usual layout
and remapping settings active.

### How each context gets the key name

- **Welcome screen and editor clipboard.** Both use Flutter's logical key and
  pressed modifier state. Flutter can assign a US-layout logical key on a
  non-Latin layout. On Linux with the standard Russian layout, the key that
  types `й` has the logical key `q` in these contexts.
  See [Flutter logical keys](https://api.flutter.dev/flutter/services/KeyEvent/logicalKey.html).
- **Native previews on Linux.** Nauvim uses GTK key events. It checks the
  unshifted and shifted mappings in the event's layout for an ASCII letter or
  digit, then uses the event's key symbol if neither is present. On the standard
  Russian layout, use `й` for the key that types `й`.
  See [GTK key events](https://docs.gtk.org/gdk3/struct.EventKey.html).
- **Native previews on macOS.** Nauvim checks the unshifted and shifted AppKit
  mappings for an ASCII letter or digit. For other keys it uses the event's
  characters as if only Shift applied. Option still counts as `Alt` in the
  chord. For example, use `Alt-e` for Option-E on the US layout, where it starts
  an accent without entering text.
  See [AppKit key event characters](https://developer.apple.com/documentation/appkit/nsevent/charactersignoringmodifiers).

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
| `paste` | Pastes the client clipboard into Neovim | `Ctrl-Shift-v` | `Super-v` |

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

The host plugin can open a preview without moving keyboard focus. A preview
opened with `focusable = false` cannot receive keyboard focus. A preview opened
with `close_on_blur = true` closes when it loses focus.

On Linux, select **Inspect Element** in the preview's context menu. On macOS
13.3 or later, open the inspector from Safari's **Develop** menu.
[WebKit Inspector documentation](https://webkit.org/blog/13936/enabling-the-inspection-of-web-content-in-apps/)
