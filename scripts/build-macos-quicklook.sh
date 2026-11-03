#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Build and embed macOS Quick Look Preview Extension (QuickLookExtension.appex)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="${1:-host}" # "host" or "universal"
APP_BUNDLE="${2:-$ROOT_DIR/ui/build/macos/Build/Products/Release/SuperGoodViewer.app}"

QL_SRC_DIR="$ROOT_DIR/ui/macos/QuickLookExtension"
APPEX_DIR="$APP_BUNDLE/Contents/PlugIns/QuickLookExtension.appex"
APPEX_CONTENTS="$APPEX_DIR/Contents"
APPEX_MACOS="$APPEX_CONTENTS/MacOS"
APPEX_BIN="$APPEX_MACOS/QuickLookExtension"

# Parse version from ui/pubspec.yaml (e.g. "1.1.1+2")
RAW_VER=$(grep -m1 '^version:' "$ROOT_DIR/ui/pubspec.yaml" | awk '{print $2}')
SHORT_VER="${RAW_VER%%+*}"
BUILD_VER="${RAW_VER#*+}"
if [ "$BUILD_VER" = "$RAW_VER" ] || [ -z "$BUILD_VER" ]; then
  BUILD_VER="1"
fi

echo "==> Building QuickLookExtension.appex (mode=$MODE, version=$SHORT_VER+$BUILD_VER)..."

rm -rf "$APPEX_DIR"
mkdir -p "$APPEX_MACOS"

cp "$QL_SRC_DIR/Info.plist" "$APPEX_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VER" "$APPEX_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VER" "$APPEX_CONTENTS/Info.plist"

SWIFTC_COMMON_FLAGS=(
  -O
  -whole-module-optimization
  -application-extension
  -module-name QuickLookExtension
  -import-objc-header "$QL_SRC_DIR/sogood_ffi.h"
  -framework Foundation
  -framework Quartz
  -framework QuickLookUI
  -framework UniformTypeIdentifiers
  -Xlinker -e
  -Xlinker _NSExtensionMain
)

if [ "$MODE" = "universal" ]; then
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  xcrun swiftc "${SWIFTC_COMMON_FLAGS[@]}" \
    -target arm64-apple-macosx12.0 \
    "$QL_SRC_DIR/PreviewProvider.swift" \
    -o "$TMP_DIR/QuickLookExtension-arm64"

  xcrun swiftc "${SWIFTC_COMMON_FLAGS[@]}" \
    -target x86_64-apple-macosx12.0 \
    "$QL_SRC_DIR/PreviewProvider.swift" \
    -o "$TMP_DIR/QuickLookExtension-x86_64"

  lipo -create \
    "$TMP_DIR/QuickLookExtension-arm64" \
    "$TMP_DIR/QuickLookExtension-x86_64" \
    -output "$APPEX_BIN"

  rm -rf "$TMP_DIR"
  trap - EXIT
else
  HOST_ARCH="$(uname -m)"
  if [ "$HOST_ARCH" = "arm64" ] || [ "$HOST_ARCH" = "aarch64" ]; then
    TARGET_TRIPLE="arm64-apple-macosx12.0"
  else
    TARGET_TRIPLE="x86_64-apple-macosx12.0"
  fi

  xcrun swiftc "${SWIFTC_COMMON_FLAGS[@]}" \
    -target "$TARGET_TRIPLE" \
    "$QL_SRC_DIR/PreviewProvider.swift" \
    -o "$APPEX_BIN"
fi

chmod +x "$APPEX_BIN"

codesign --force --sign - \
  --entitlements "$QL_SRC_DIR/QuickLookExtension.entitlements" \
  "$APPEX_DIR"

echo "==> Built QuickLookExtension.appex ($(lipo -archs "$APPEX_BIN"))"
