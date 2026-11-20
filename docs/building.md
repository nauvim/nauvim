# Build and run Nauvim

## Toolchain and native dependencies

Use Flutter 3.50+, Dart 3.14+, and Rust 1.89+. The Rust dependencies come from
crates.io; sibling repositories are not needed. Each editor host needs Neovim
v0.12.6.

On Linux x86-64 or aarch64, install Flutter's desktop prerequisites, WebKitGTK 4.1,
and Fontconfig headers. For Debian/Ubuntu:

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev libfontconfig1-dev
```

On macOS Apple Silicon, install Xcode and its command-line tools. Native previews
use WKWebView.

## Release build

Run from the repository root:

```sh
flutter pub get
tool/build.sh
```

`tool/build.sh` builds Rust before Flutter and packages the native library. The
scripts use POSIX `sh`.

| Platform | Output |
| --- | --- |
| Linux x86-64 | `build/linux/x64/release/bundle/nauvim` |
| Linux aarch64 | `build/linux/arm64/release/bundle/nauvim` |
| macOS | `build/macos/Build/Products/Release/Nauvim.app` |

Keep the Linux bundle directory intact when copying the application. On macOS,
copy the `.app` bundle. The macOS build script installs the Rust library in the
bundle and applies an ad-hoc signature.

## Development run

```sh
tool/run.sh -d linux
```

Use `-d macos` on macOS. The script builds a debug Rust library before starting
Flutter. Run it again after Rust changes; Flutter hot reload does not rebuild
Rust.

[Configure fonts, window size, and hosts](../README.md#configuration-and-connections)
before connecting. See [display troubleshooting](troubleshooting.md#display-and-rendering)
for renderer selection and the [development guide](development.md) for checks.
