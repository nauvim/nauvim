# Build and run Nauvim

## Toolchain and native dependencies

Use Flutter 3.50 or newer, Dart 3.14 or newer, and Rust 1.89 or newer on the
machine building Nauvim. Each editor host needs Neovim v0.12.6.

On Linux x86-64 or aarch64, install Flutter's desktop prerequisites, WebKitGTK 4.1,
and Fontconfig headers. On Debian or Ubuntu, install these packages.

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev libfontconfig1-dev
```

On macOS Apple Silicon, install Xcode and its command-line tools.

## Release build

Run the build from the repository root.

```sh
tool/build.sh
```

| Platform | What to launch |
| --- | --- |
| Linux x86-64 | `build/linux/x64/release/bundle/nauvim` |
| Linux aarch64 | `build/linux/arm64/release/bundle/nauvim` |
| macOS | `build/macos/Build/Products/Release/Nauvim.app` |

When installing elsewhere, copy the complete Linux bundle directory or macOS
`.app` bundle.

See [configuration](configuration.md) to set up hosts, fonts, or shortcuts.
For display issues, see [troubleshooting](troubleshooting.md#display-and-rendering).

<a id="development-run"></a>

For a debug build or live development, use the
[development guide](development.md#run-a-debug-build).
