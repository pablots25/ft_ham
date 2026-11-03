#!/usr/bin/env bash
# Builds WsprFFI.xcframework (device + simulator) from this crate. Run on macOS with Xcode
# and rustup installed:
#
#   ./rust/wspr_ffi/build-ios.sh
#
# Output: rust/wspr_ffi/build/WsprFFI.xcframework — drag it into the ft8_ham target
# ("Frameworks, Libraries, and Embedded Content", Do Not Embed: it is a static library).
set -euo pipefail
cd "$(dirname "$0")"

IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-16.0}"
export IPHONEOS_DEPLOYMENT_TARGET

TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)
# rust-toolchain.toml pins the toolchain and lists the targets; make sure they exist.
rustup target add "${TARGETS[@]}" >/dev/null

for t in "${TARGETS[@]}"; do
  echo "==> cargo build --release --target $t"
  cargo build --release --target "$t" --lib
done

BUILD=build
rm -rf "$BUILD"
mkdir -p "$BUILD/sim" "$BUILD/headers"
cp include/wspr_ffi.h include/module.modulemap "$BUILD/headers/"

# One fat simulator library (arm64 + x86_64).
lipo -create \
  target/aarch64-apple-ios-sim/release/libwspr_ffi.a \
  target/x86_64-apple-ios/release/libwspr_ffi.a \
  -output "$BUILD/sim/libwspr_ffi.a"

xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libwspr_ffi.a -headers "$BUILD/headers" \
  -library "$BUILD/sim/libwspr_ffi.a" -headers "$BUILD/headers" \
  -output "$BUILD/WsprFFI.xcframework"

echo "==> $BUILD/WsprFFI.xcframework"
