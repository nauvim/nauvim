#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
platform=$(uname -s)
case "$platform" in
  Linux) ;;
  Darwin) export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-12.0} ;;
  *) echo 'Nauvim currently supports Linux and macOS.' >&2; exit 1 ;;
esac

cargo build --manifest-path rust/Cargo.toml --release --locked
flutter pub get --enforce-lockfile
case "$platform" in
  Linux) flutter build linux --release --no-pub "$@" ;;
  Darwin)
    flutter build macos --release --no-pub "$@"
    destination="build/macos/Build/Products/Release/Nauvim.app/Contents/Frameworks"
    mkdir -p "$destination"
    cp rust/target/release/libnauvim_flutter.dylib "$destination/"
    codesign --force --deep --sign - build/macos/Build/Products/Release/Nauvim.app
    ;;
esac
