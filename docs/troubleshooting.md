# Troubleshooting

After the window opens, check the error banner below the toolbar.

## Display and rendering

If the UI appears shifted outside its window on Linux, try software rendering.
Nauvim selects it automatically on X11 with a single NVIDIA adapter and the
affected Flutter 3.50.0 engine. [Flutter issue #195885](https://github.com/flutter/flutter/issues/195885)

Set `FLUTTER_LINUX_RENDERER` to override automatic renderer selection.

```sh
FLUTTER_LINUX_RENDERER=software build/linux/x64/release/bundle/nauvim
```

For an unexpected font, check the configured family and file.
[Font settings](configuration.md#fonts)

Maximized or tiled windows can have extra space around the editor when the
window size leaves a partial cell. [Window settings](configuration.md#window)

## Configuration errors

| Symptom | What to check |
| --- | --- |
| Configured hosts are missing | Confirm the file location or pass its path with `--config`. [Configuration file location](configuration.md#configuration-file-location) |
| Fonts, window, and keys use defaults | Check the `ui_opts` entry selected by `use_ui_opts` or the default UI ID. [UI options](configuration.md#ui-options) |
| The banner reports a configuration error | Correct the reported setting. Nauvim uses built-in settings after a load or validation failure. [Configuration fallback](configuration.md#configuration-fallback) |
| The banner reports an unavailable font | Check the exact family name and the font file path. [Font settings](configuration.md#fonts) |

Restart Nauvim after making changes.

<a id="input-and-connection-behavior"></a>

## Connection errors

When the host exits or a connection fails, Nauvim returns to the welcome page.

1. Run `nvim --version` on the machine running Neovim. Nauvim targets v0.12.6.
   Set the executable path if the host needs a different `nvim`.
   [Neovim executable](configuration.md#neovim-program-and-socket)
2. For SSH, check the destination, credentials, and host key in the
   `known_hosts` file. The server must allow SFTP and Unix socket forwarding.
   [SSH settings](configuration.md#ssh)
3. Select the destination again. The connected host appears in the toolbar.

### Blank buffers after reattachment

Nauvim uses the saved [UI checkpoint](persistence.md#session-ui-checkpoints)
to restore the buffer contents and window layout when you reattach to the
same Neovim process.

When no matching checkpoint is available, Neovim v0.12.6 can show a statusline
with blank buffers after reattachment. The buffers remain open in Neovim.
Check that the destination still points to the same Neovim session and socket.
[Neovim issue #30583](https://github.com/neovim/neovim/issues/30583)
