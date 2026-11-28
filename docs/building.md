# Build and run Nauvim

<a id="toolchain-and-native-dependencies"></a>

## Build-time prerequisites

Install Flutter 3.50+ (with Dart 3.14+) and Rust 1.89+ with Cargo.

### Linux

Debian or Ubuntu, x86-64 or aarch64.
[Flutter Linux setup](https://docs.flutter.dev/platform-integration/linux/setup)

```sh
sudo apt install build-essential clang cmake ninja-build pkg-config \
  libgtk-3-dev libwebkit2gtk-4.1-dev libfontconfig1-dev
```

### macOS

Apple Silicon with Xcode and its command-line tools.
[Flutter macOS setup](https://docs.flutter.dev/platform-integration/macos/setup)

## Runtime prerequisites

### Machine running Nauvim

| Platform | GUI runtime | Clipboard paste and host copies |
| --- | --- | --- |
| Linux x86-64 or aarch64 | Desktop with GTK 3, WebKitGTK 4.1, Fontconfig, and the C++ runtime | `wl-clipboard` on Wayland. `xclip` or `xsel` on X11. |
| Apple Silicon | macOS 12.0+ with system WebKit | System `pbcopy` and `pbpaste` |

Ubuntu 24.04 runtime packages.

```sh
sudo apt install libgtk-3-0t64 libwebkit2gtk-4.1-0 libfontconfig1 libstdc++6
```

Debian 12 uses `libgtk-3-0`. [Ubuntu packages](https://packages.ubuntu.com/noble/libwebkit2gtk-4.1-0) · [Debian packages](https://packages.debian.org/bookworm/libwebkit2gtk-4.1-0) · [Clipboard settings](configuration.md#clipboard)

### Machine running Neovim

| When | Requirement |
| --- | --- |
| Local or remote | Neovim v0.12.6 on the GUI machine (local) or SSH server (remote). Default executable is `nvim` on the host's `PATH`. [Executable settings](configuration.md#neovim-program-and-socket) |
| SSH | Server-side command execution, SFTP, and Unix socket forwarding. Configure credentials on the GUI machine. [SSH setup](configuration.md#ssh) |
| Host clipboard copies or web previews | [Install nauvim-plugin](https://github.com/nauvim/nauvim-plugin#install) on the host and [grant permissions](configuration.md#host-plugin-permissions). |

## Release build

Run the build from the repository root.

```sh
tool/build.sh
```

## Launch the bundle

Run the command for your platform from the repository root.

| Platform | Launch command |
| --- | --- |
| Linux x86-64 | `build/linux/x64/release/bundle/nauvim` |
| Linux aarch64 | `build/linux/arm64/release/bundle/nauvim` |
| macOS | `open build/macos/Build/Products/Release/Nauvim.app` |

On a first launch with default settings, Nauvim opens a local Neovim session.
When the welcome page appears, select a destination to open the editor.
[Connect from the welcome page](configuration.md#connect-from-the-welcome-page)

Use a bundle built for your architecture and OS. Copy the complete bundle
when installing elsewhere.

To add Nauvim to a Linux desktop menu, make the bundle's `nauvim` command
available on `PATH`. Copy the `applications` and `icons` directories from the
bundle's `share/` directory into `$XDG_DATA_HOME` (default `~/.local/share`).

[Troubleshoot connections](troubleshooting.md#connection-errors) ·
[Troubleshoot display problems](troubleshooting.md#display-and-rendering)

<a id="development-run"></a>

[Debug builds](development.md#run-a-debug-build)
