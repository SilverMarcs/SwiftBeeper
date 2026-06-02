#!/usr/bin/env bash
# Build the EasyMatrix Go backend as a C static-library xcframework that the
# Relay app links and runs IN-PROCESS on both macOS and iOS.
#
# This replaces the old "spawn a subprocess" model (impossible on iOS): the Go
# server is compiled with `-buildmode=c-archive` into per-platform static
# libraries, combined into EasyMatrix.xcframework, and started inside the app
# via the EasyMatrix* C exports (see cmd/ffi/main.go). The `goolm` build tag
# selects mautrix's pure-Go olm implementation, so there is NO libolm C++
# dependency to cross-compile or bundle.
#
# Usage:
#   build-easymatrix-xcframework.sh [all|macos|ios]   (default: all)
#
# Output: Relay/Frameworks/EasyMatrix.xcframework

set -euo pipefail

WHAT="${1:-all}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .../Relay/Relay/Helpers -> project root that holds Relay.xcodeproj is .../Relay/Relay
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EASYMATRIX_DIR="$(cd "$PROJECT_ROOT/../EasyMatrix" && pwd)"
OUT_DIR="$PROJECT_ROOT/Frameworks"
BUILD_DIR="$(mktemp -d)"
XCFRAMEWORK="$OUT_DIR/EasyMatrix.xcframework"

IOS_MIN="26.0"
MACOS_MIN="26.2"
GO_TAGS="goolm"
PKG="./cmd/ffi"

trap 'rm -rf "$BUILD_DIR"' EXIT

if command -v go >/dev/null 2>&1; then GO_BIN=go
elif [ -x /opt/homebrew/bin/go ]; then GO_BIN=/opt/homebrew/bin/go
elif [ -x /usr/local/bin/go ]; then GO_BIN=/usr/local/bin/go
elif [ -x /usr/local/go/bin/go ]; then GO_BIN=/usr/local/go/bin/go
else echo "error: go not found" >&2; exit 1; fi

cd "$EASYMATRIX_DIR"

# build_slice <goos> <goarch> <sdk> <clang-target> <out-subdir>
build_slice() {
    local goos="$1" goarch="$2" sdk="$3" target="$4" sub="$5"
    local sdkpath clang dir
    sdkpath="$(xcrun --sdk "$sdk" --show-sdk-path)"
    clang="$(xcrun --sdk "$sdk" -f clang)"
    dir="$BUILD_DIR/$sub"
    mkdir -p "$dir"

    # Go uses GOARCH amd64/arm64; clang uses x86_64/arm64.
    local clang_arch="$goarch"
    [ "$goarch" = "amd64" ] && clang_arch="x86_64"
    local cflags="-isysroot $sdkpath -arch $clang_arch"
    [ -n "$target" ] && cflags="$cflags -target $target"

    echo ">> building $goos/$goarch ($sdk${target:+, $target})"
    local clangxx
    clangxx="$(xcrun --sdk "$sdk" -f clang++)"
    GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=1 \
        CC="$clang $cflags" \
        CXX="$clangxx $cflags" \
        CGO_CFLAGS="$cflags" \
        CGO_CXXFLAGS="$cflags" \
        CGO_LDFLAGS="$cflags" \
        "$GO_BIN" build -tags "$GO_TAGS" -trimpath -ldflags "-s -w" \
        -buildmode=c-archive -o "$dir/libeasymatrix.a" "$PKG"
}

# Combine multiple single-arch slices into one fat static lib + headers dir.
# package_lib <out-name> <slice-dir-1> [slice-dir-2 ...]
package_lib() {
    local name="$1"; shift
    local dest="$BUILD_DIR/pkg/$name"
    mkdir -p "$dest/Headers"
    local libs=()
    for d in "$@"; do libs+=("$d/libeasymatrix.a"); done
    if [ "${#libs[@]}" -gt 1 ]; then
        lipo -create "${libs[@]}" -output "$dest/libeasymatrix.a"
    else
        cp "${libs[0]}" "$dest/libeasymatrix.a"
    fi
    # The cgo-generated header is identical across arches; take it from the first.
    cp "$(dirname "${libs[0]}")/libeasymatrix.h" "$dest/Headers/libeasymatrix.h"
    echo "$dest"
}

LIB_ARGS=()

if [ "$WHAT" = "all" ] || [ "$WHAT" = "macos" ]; then
    build_slice darwin arm64 macosx "" mac-arm64
    build_slice darwin amd64 macosx "" mac-amd64
    MAC_PKG="$(package_lib macos "$BUILD_DIR/mac-arm64" "$BUILD_DIR/mac-amd64")"
    LIB_ARGS+=(-library "$MAC_PKG/libeasymatrix.a" -headers "$MAC_PKG/Headers")
fi

if [ "$WHAT" = "all" ] || [ "$WHAT" = "ios" ]; then
    build_slice ios arm64 iphoneos "arm64-apple-ios${IOS_MIN}" ios-arm64
    IOS_PKG="$(package_lib ios-device "$BUILD_DIR/ios-arm64")"
    LIB_ARGS+=(-library "$IOS_PKG/libeasymatrix.a" -headers "$IOS_PKG/Headers")

    build_slice ios arm64 iphonesimulator "arm64-apple-ios${IOS_MIN}-simulator" sim-arm64
    build_slice ios amd64 iphonesimulator "x86_64-apple-ios${IOS_MIN}-simulator" sim-amd64
    SIM_PKG="$(package_lib ios-sim "$BUILD_DIR/sim-arm64" "$BUILD_DIR/sim-amd64")"
    LIB_ARGS+=(-library "$SIM_PKG/libeasymatrix.a" -headers "$SIM_PKG/Headers")
fi

if [ "${#LIB_ARGS[@]}" -eq 0 ]; then
    echo "error: nothing to build for '$WHAT'" >&2; exit 1
fi

echo ">> assembling $XCFRAMEWORK"
rm -rf "$XCFRAMEWORK"
mkdir -p "$OUT_DIR"
xcodebuild -create-xcframework "${LIB_ARGS[@]}" -output "$XCFRAMEWORK"
echo "done: $XCFRAMEWORK"
