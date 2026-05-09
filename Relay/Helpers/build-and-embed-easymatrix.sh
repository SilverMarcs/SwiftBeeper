#!/usr/bin/env bash
# Build the EasyMatrix Go binary, embed it in Contents/Helpers/, and bundle
# its libolm dependency in Contents/Frameworks/ with rewritten load paths so
# the shipped .app doesn't depend on the user having Homebrew.
#
# Invoked by the "Embed EasyMatrix" Xcode build phase. Relies on Xcode env:
#   SRCROOT, TARGET_BUILD_DIR, CONTENTS_FOLDER_PATH, EXPANDED_CODE_SIGN_IDENTITY

set -euo pipefail

if command -v go >/dev/null 2>&1; then
    GO_BIN=go
elif [ -x /opt/homebrew/bin/go ]; then
    GO_BIN=/opt/homebrew/bin/go
elif [ -x /usr/local/bin/go ]; then
    GO_BIN=/usr/local/bin/go
elif [ -x /usr/local/go/bin/go ]; then
    GO_BIN=/usr/local/go/bin/go
else
    echo "error: go not found in PATH or common install locations" >&2
    exit 1
fi

LIBOLM_PREFIX=""
if command -v brew >/dev/null 2>&1; then
    LIBOLM_PREFIX="$(brew --prefix libolm 2>/dev/null || true)"
fi
if [ -z "$LIBOLM_PREFIX" ]; then
    if [ -d /opt/homebrew/opt/libolm ]; then
        LIBOLM_PREFIX=/opt/homebrew/opt/libolm
    elif [ -d /usr/local/opt/libolm ]; then
        LIBOLM_PREFIX=/usr/local/opt/libolm
    fi
fi
if [ -z "$LIBOLM_PREFIX" ] || [ ! -f "$LIBOLM_PREFIX/include/olm/olm.h" ]; then
    echo "error: libolm not found. Install with: brew install libolm" >&2
    exit 1
fi

EASYMATRIX_DIR="$SRCROOT/../EasyMatrix"
HELPERS_DIR="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
FRAMEWORKS_DIR="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Frameworks"

mkdir -p "$HELPERS_DIR" "$FRAMEWORKS_DIR"

echo "Building easymatrix from $EASYMATRIX_DIR (libolm: $LIBOLM_PREFIX)"
cd "$EASYMATRIX_DIR"
export CGO_ENABLED=1
export CGO_CFLAGS="-I${LIBOLM_PREFIX}/include"
export CGO_LDFLAGS="-L${LIBOLM_PREFIX}/lib -lolm"
"$GO_BIN" build -trimpath -ldflags "-s -w" -o "$HELPERS_DIR/easymatrix" ./cmd/server

LIBOLM_SRC="$LIBOLM_PREFIX/lib/libolm.3.dylib"
if [ ! -f "$LIBOLM_SRC" ]; then
    LIBOLM_SRC="$LIBOLM_PREFIX/lib/libolm.dylib"
fi
LIBOLM_BUNDLED="$FRAMEWORKS_DIR/libolm.3.dylib"
cp "$LIBOLM_SRC" "$LIBOLM_BUNDLED"
chmod 644 "$LIBOLM_BUNDLED"

OLM_DEP="$(otool -L "$HELPERS_DIR/easymatrix" | awk '/libolm.*dylib/ {print $1; exit}')"
if [ -n "$OLM_DEP" ]; then
    install_name_tool -change "$OLM_DEP" "@executable_path/../Frameworks/libolm.3.dylib" "$HELPERS_DIR/easymatrix"
fi
install_name_tool -id "@executable_path/../Frameworks/libolm.3.dylib" "$LIBOLM_BUNDLED"

SIGN_ID="${EXPANDED_CODE_SIGN_IDENTITY:--}"
echo "Signing libolm and easymatrix with identity: $SIGN_ID"
codesign --force --sign "$SIGN_ID" --options runtime --timestamp=none "$LIBOLM_BUNDLED"
codesign --force --sign "$SIGN_ID" --options runtime --timestamp=none "$HELPERS_DIR/easymatrix"
