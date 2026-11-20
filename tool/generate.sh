#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
flutter pub get
if [ "$(flutter_rust_bridge_codegen --version)" != "flutter_rust_bridge_codegen 2.13.0" ]; then
  echo 'Install flutter_rust_bridge_codegen 2.13.0 to match the pinned bridge runtime.' >&2
  exit 1
fi
flutter_rust_bridge_codegen generate
cargo fmt --manifest-path rust/Cargo.toml
