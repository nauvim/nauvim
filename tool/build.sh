#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
cargo build --manifest-path rust/Cargo.toml --release
flutter pub get
case "$(uname -s)" in
  Linux) flutter build linux --release --no-pub "$@" ;;
  Darwin)
    flutter build macos --release --no-pub "$@"
    destination="build/macos/Build/Products/Release/Nauvim.app/Contents/Frameworks"
    mkdir -p "$destination"
    cp rust/target/release/libnauvim_flutter.dylib "$destination/"
    codesign --force --deep --sign - build/macos/Build/Products/Release/Nauvim.app
    ;;
  *) echo 'Nauvim currently supports Linux and macOS.' >&2; exit 1 ;;
esac
