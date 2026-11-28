# Nauvim

<img src="assets/nauvim-logo.svg" alt="Nauvim logo" width="160" height="160">

Logo by Masato Nakata. [Source](https://github.com/nauvim/nauvim-logo) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Nauvim is a Flutter desktop GUI for Neovim on Linux and macOS. Connect to a
local or SSH host and return to the same editor session after closing the GUI.

<a id="requirements"></a>

## Build and run

Use the [build guide](docs/building.md) for platform requirements, the release
build command, and the location of the application bundle.

## Configuration and connections

<a id="ui-options"></a>
<a id="key-bindings"></a>
<a id="appendix-opentype-font-selection"></a>
<a id="connections-and-welcome-keys"></a>

- [Configure Nauvim](docs/configuration.md) for the location of `init.lua`,
  a complete example, and settings for hosts and the window.
- [Choose fonts](docs/configuration.md#fonts) for family names, font files,
  and glyph fallback.
- [Configure key bindings](docs/key-bindings.md) for default bindings and
  overrides for the welcome page, clipboard, and web previews.
- [Install nauvim-plugin in Neovim](https://github.com/nauvim/nauvim-plugin#install)
  for host-side clipboard and plugin integration. Ordinary editing works without it.

## Editing and lifecycle

Editing keys follow your Neovim mappings. Drag to select text within a grid.
By default, copy and paste use Ctrl-Shift-c and Ctrl-Shift-v on Linux and
Command-c and Command-v on macOS. Nauvim uses mouse input for GUI controls
and text selection. The focused editor uses native text input by default. See
[native text input](docs/configuration.md#native-text-input) to select the input
route.

Use the detach button or Neovim's `:detach` command to return to the welcome
page. Closing Nauvim leaves host Neovim processes running for reattachment.

## Troubleshooting

- [Troubleshooting](docs/troubleshooting.md) covers display problems,
  configuration errors, and reattachment.
- [Saved data](docs/persistence.md) shows how to reset the remembered host
  or clear the font cache.

<a id="changing-the-design"></a>

## Development and validation

- [Development guide](docs/development.md) for running and testing changes.
- [Flutter design guide](docs/architecture.md) and [Rust architecture](rust/README.md)
  for changing the frontend.
- [Nauvim specification v1.3.0](https://github.com/nauvim/nauvim-spec/blob/v1.3.0/specification.md)
  for shared session, configuration, and plugin contracts.
