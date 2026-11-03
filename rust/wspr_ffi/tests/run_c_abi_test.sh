#!/usr/bin/env bash
# Builds the static library for the host and runs the C ABI test against it.
set -euo pipefail
cd "$(dirname "$0")/.."
cargo build --release
LIB=target/release/libwspr_ffi.a
OUT=target/c_abi_test
EXTRA=""
case "$(uname)" in
  Linux) EXTRA="-lpthread -ldl -lm" ;;
  Darwin) EXTRA="-framework CoreFoundation" ;;
esac
cc -O2 -Iinclude tests/c_abi_test.c "$LIB" $EXTRA -o "$OUT"
"$OUT"
