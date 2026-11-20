#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
cargo build --manifest-path rust/Cargo.toml
export NAUVIM_LIBRARY="$PWD/rust/target/debug/libnauvim_flutter.so"
if [ "$(uname -s)" = Darwin ]; then
  export NAUVIM_LIBRARY="$PWD/rust/target/debug/libnauvim_flutter.dylib"
fi
flutter run "$@"
