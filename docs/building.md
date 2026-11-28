<a id="build-and-run-nauvim"></a>

# Install and run Nauvim

## Install a release

Download the archive for your system from
[GitHub Releases](https://github.com/nauvim/nauvim/releases). Install the
[runtime prerequisites](#runtime-prerequisites) before opening the app.

### Linux

The release archives are built on Ubuntu 24.04. Choose the `linux-x64` archive
for x86-64 or the `linux-arm64` archive for aarch64. Extract the archive and keep
the whole `nauvim` directory together.

For example, to extract and run v1.0.2 on x86-64, use the following commands.

```sh
tar -xzf nauvim-v1.0.2-linux-x64.tar.gz
./nauvim/nauvim
```

To add Nauvim to your applications menu, move the extracted directory to
where you want to keep it. Run `./nauvim/install-desktop-entry.sh` from its
parent directory to install the launcher and icon for your account. Then
open **Nauvim** from the menu. Run the script again if you move the bundle.

If the bundle path contains characters that need escaping, edit the `Exec` line
in `com.naughie.nauvim.flutter.desktop` under `$XDG_DATA_HOME/applications`
(default `~/.local/share/applications`).

### macOS

Download the `macos-arm64-unnotarized.zip` archive for Apple Silicon. Verify
its [checksum](#verify-a-download), extract it, move `Nauvim.app` to
Applications, and try to open it.

The app is signed ad hoc and has no Apple notarization. If macOS says it
cannot verify the developer or check the app for malicious software, you can
approve this copy of Nauvim after verifying the download from the official
GitHub release. Open **System Settings → Privacy & Security**, click
**Open Anyway** for Nauvim, and confirm. On macOS 12, find **Open Anyway**
in **System Preferences → Security & Privacy → General**.
[Apple's first-launch instructions](https://support.apple.com/en-us/102445)

A managed Mac may restrict app approval. You can also
[build Nauvim from source](#build-time-prerequisites).

### Verify a download

Download `SHA256SUMS` from the same release. Run `sha256sum --ignore-missing -c SHA256SUMS`
on Linux in the directory containing the downloaded archive. On macOS, run
`shasum -a 256` with the archive filename and compare the result with its line
in `SHA256SUMS`.

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

<a id="toolchain-and-native-dependencies"></a>

## Build-time prerequisites

The release workflow uses Flutter 3.50.0 (with Dart 3.14.0) and Rust 1.100.0
with Cargo. Use these versions to build with the checked-in lockfiles.

On Debian or Ubuntu, install the Linux build dependencies.
[Flutter Linux setup](https://docs.flutter.dev/platform-integration/linux/setup)

```sh
sudo apt install build-essential clang cmake ninja-build pkg-config \
  libgtk-3-dev libwebkit2gtk-4.1-dev libfontconfig1-dev
```

On Linux ARM64, check out the [Flutter 3.50.0 Git tag](https://github.com/flutter/flutter/tree/3.50.0)
and run `bin/flutter precache --linux` from the Flutter checkout.

On Apple Silicon, install Xcode and its command-line tools.
[Flutter macOS setup](https://docs.flutter.dev/platform-integration/macos/setup)

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

## First launch

On a first launch with default settings, Nauvim opens a local Neovim session.
When the welcome page appears, select a destination to open the editor.
[Connect from the welcome page](configuration.md#connect-from-the-welcome-page)

[Troubleshoot connections](troubleshooting.md#connection-errors) ·
[Troubleshoot display problems](troubleshooting.md#display-and-rendering)

<a id="development-run"></a>

[Debug builds](development.md#run-a-debug-build)
