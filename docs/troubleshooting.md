# Troubleshooting

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

If Nauvim opens with default settings or skips a font, check the error display.
Correct the indicated setting or font path, then restart Nauvim.
[Configuration fallback](configuration.md#configuration-fallback)

<a id="input-and-connection-behavior"></a>

## Connection errors

When the host exits or a connection fails, Nauvim returns to the welcome page.
Check the error display, then select the host again.

### Blank buffers after reattachment

Neovim v0.12.6 can show a statusline with blank buffers after reattachment.
The buffers remain open in Neovim. Nauvim restores the initial contents when
it is the only attached UI.
[Neovim issue #30583](https://github.com/neovim/neovim/issues/30583)

If the buffers are blank, detach any other UIs from the same Neovim process.
Then detach and reconnect Nauvim.
