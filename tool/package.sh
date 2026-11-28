#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

tag=${1:-}
if [ "$#" -ne 1 ] ||
    ! printf '%s\n' "$tag" | grep -Eq '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
  echo 'Usage: tool/package.sh vX.Y.Z' >&2
  exit 1
fi

case "$(uname -s):$(uname -m)" in
  Linux:x86_64) platform=linux-x64 ;;
  Linux:aarch64) platform=linux-arm64 ;;
  Darwin:arm64) platform=macos-arm64 ;;
  *) echo 'Unsupported release platform.' >&2; exit 1 ;;
esac

out="$PWD/build/dist"
mkdir -p "$out"
stage=$(mktemp -d "$out/.package.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT
name="nauvim-$tag-$platform"

case "$platform" in
  linux-*)
    bundle="build/linux/${platform#linux-}/release/bundle"
    test -x "$bundle/nauvim"
    test -s "$bundle/lib/libnauvim_flutter.so"
    test -s "$bundle/lib/libflutter_linux_gtk.so"
    test -s "$bundle/lib/libapp.so"
    test -s "$bundle/data/icudtl.dat"
    test -s "$bundle/data/flutter_assets/NOTICES.Z"
    test -s "$bundle/share/applications/com.naughie.nauvim.flutter.desktop"
    test -s "$bundle/share/icons/hicolor/256x256/apps/com.naughie.nauvim.flutter.png"
    test -x "$bundle/install-desktop-entry.sh"
    jq -e --arg version "${tag#v}" '.version == $version' \
      "$bundle/data/flutter_assets/version.json" > /dev/null
    cp -R "$bundle" "$stage/nauvim"
    ;;
  macos-arm64)
    bundle=build/macos/Build/Products/Release/Nauvim.app
    frameworks="$bundle/Contents/Frameworks"
    plist="$bundle/Contents/Info.plist"
    version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist")
    test "$version" = "${tag#v}"
    test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$plist")" = com.naughie.nauvim.flutter
    test "$(lipo -archs "$bundle/Contents/MacOS/Nauvim")" = arm64
    lipo "$frameworks/App.framework/App" -verify_arch arm64
    lipo "$frameworks/FlutterMacOS.framework/FlutterMacOS" -verify_arch arm64
    lipo "$frameworks/libnauvim_flutter.dylib" -verify_arch arm64
    mkdir "$stage/nauvim"
    ditto "$bundle" "$stage/nauvim/Nauvim.app"
    codesign --verify --deep --strict "$stage/nauvim/Nauvim.app"
    ;;
esac

cp LICENSE-APACHE LICENSE-MIT "$stage/nauvim/"
target=$(rustc --print host-tuple)
cargo about generate --locked --fail --target "$target" \
  --manifest-path rust/Cargo.toml --output-file "$stage/nauvim/RUST-LICENSES.html" \
  rust/about.hbs

case "$platform" in
  linux-*)
    archive="$name.tar.gz"
    tar -czf "$stage/$archive" -C "$stage" nauvim
    ;;
  macos-arm64)
    archive="$name-unnotarized.zip"
    ditto -c -k --keepParent "$stage/nauvim" "$stage/$archive"
    ;;
esac

mv "$stage/$archive" "$out/"
printf '%s\n' "build/dist/$archive"
