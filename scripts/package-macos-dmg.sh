#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Package macOS Standalone DMGs for Universal, Apple Silicon (arm64), and Intel (x64)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE_APP="${SOURCE_APP:-$ROOT_DIR/ui/build/macos/Build/Products/Release/SuperGoodViewer.app}"
TARGET_MODE="${1:-universal}" # universal, arm64, x64, all, or all-with-universal
OUTPUT_DIR="${2:-${OUTPUT_DIR:-$ROOT_DIR/dist}}"
VERSION_TAG="${3:-${RELEASE_VERSION:-}}"

if [ ! -d "$SOURCE_APP" ] || [ ! -f "$SOURCE_APP/Contents/MacOS/SuperGoodViewer" ]; then
  echo "::error::Source App Bundle not found at: $SOURCE_APP"
  echo "Please build the macOS app first (e.g. 'make build' or 'flutter build macos --release')."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

package_universal() {
  local dmg_filename=""
  if [ -n "$VERSION_TAG" ]; then
    dmg_filename="SuperGoodViewer-${VERSION_TAG}-macos.dmg"
  else
    dmg_filename="SuperGoodViewer-macos.dmg"
  fi

  local dmg_out="$OUTPUT_DIR/$dmg_filename"
  local staging_dir="$ROOT_DIR/build/dmg-staging-universal"

  echo "================================================================="
  echo "==> Packaging Universal macOS DMG (arm64 + x86_64)"
  echo "    Output DMG: $dmg_out"
  echo "================================================================="

  rm -rf "$staging_dir"
  mkdir -p "$staging_dir"

  echo "  -> Staging clean App Bundle copy..."
  cp -R "$SOURCE_APP" "$staging_dir/SuperGoodViewer.app"

  echo "  -> Verifying universal architectures on main executable..."
  local main_arch
  main_arch=$(lipo -archs "$staging_dir/SuperGoodViewer.app/Contents/MacOS/SuperGoodViewer")
  echo "     SuperGoodViewer architectures: $main_arch"
  echo "$main_arch" | grep -qw arm64 || { echo "::error::SuperGoodViewer missing arm64 slice"; exit 1; }
  echo "$main_arch" | grep -qw x86_64 || { echo "::error::SuperGoodViewer missing x86_64 slice"; exit 1; }

  # Re-signing
  echo "  -> Re-signing app bundle (ad-hoc)..."
  codesign --force --deep --sign - "$staging_dir/SuperGoodViewer.app"
  codesign --verify --deep --strict "$staging_dir/SuperGoodViewer.app"
  echo "     Codesign validation passed."

  # Prepare DMG layout
  echo "  -> Adding /Applications symlink..."
  ln -s /Applications "$staging_dir/Applications"

  # Create DMG
  echo "  -> Creating DMG with hdiutil..."
  rm -f "$dmg_out"
  hdiutil create -volname "超好读 SuperGoodViewer" \
    -srcfolder "$staging_dir" \
    -ov -format UDZO \
    "$dmg_out"

  # Cleanup staging
  rm -rf "$staging_dir"

  echo "==> Universal DMG successfully created: $dmg_out"
  ls -lh "$dmg_out"
  echo ""
}

package_arch() {
  local arch_name="$1"      # "arm64" or "x64"
  local target_arch=""       # "arm64" or "x86_64" for lipo

  if [ "$arch_name" = "arm64" ]; then
    target_arch="arm64"
  elif [ "$arch_name" = "x64" ] || [ "$arch_name" = "x86_64" ]; then
    arch_name="x64"
    target_arch="x86_64"
  else
    echo "::error::Unknown architecture: $arch_name (expected 'arm64' or 'x64')"
    exit 1
  fi

  local dmg_filename=""
  if [ -n "$VERSION_TAG" ]; then
    dmg_filename="SuperGoodViewer-${VERSION_TAG}-macos-${arch_name}.dmg"
  else
    dmg_filename="SuperGoodViewer-macos-${arch_name}.dmg"
  fi

  local dmg_out="$OUTPUT_DIR/$dmg_filename"
  local staging_dir="$ROOT_DIR/build/dmg-staging-${arch_name}"

  echo "================================================================="
  echo "==> Packaging macOS DMG: $arch_name ($target_arch)"
  echo "    Output DMG: $dmg_out"
  echo "================================================================="

  rm -rf "$staging_dir"
  mkdir -p "$staging_dir"

  echo "  -> Staging clean App Bundle copy..."
  cp -R "$SOURCE_APP" "$staging_dir/SuperGoodViewer.app"

  echo "  -> Thinning all universal Mach-O binaries to $target_arch..."
  local thinned_count=0
  while IFS= read -r -d '' file; do
    if file "$file" | grep -q "Mach-O"; then
      local archs
      archs=$(lipo -archs "$file" 2>/dev/null || true)
      if echo "$archs" | grep -qw "$target_arch"; then
        local count
        count=$(echo "$archs" | wc -w)
        if [ "$count" -gt 1 ]; then
          echo "     [lipo -thin] $(basename "$file") ($archs) -> $target_arch"
          lipo -thin "$target_arch" "$file" -output "$file"
          thinned_count=$((thinned_count + 1))
        fi
      else
        echo "::warning::File $file does not contain target slice $target_arch (has: $archs)"
      fi
    fi
  done < <(find "$staging_dir/SuperGoodViewer.app" -type f -print0)

  echo "  -> Thinned $thinned_count binary/library slices to $target_arch."

  # Verification
  echo "  -> Verifying single architecture on main executable..."
  local main_arch
  main_arch=$(lipo -archs "$staging_dir/SuperGoodViewer.app/Contents/MacOS/SuperGoodViewer")
  if [ "$main_arch" != "$target_arch" ]; then
    echo "::error::Main executable architecture is '$main_arch', expected '$target_arch'"
    exit 1
  fi
  echo "     Verified: SuperGoodViewer architecture = $main_arch"

  # Re-signing
  echo "  -> Re-signing app bundle (ad-hoc)..."
  codesign --force --deep --sign - "$staging_dir/SuperGoodViewer.app"
  codesign --verify --deep --strict "$staging_dir/SuperGoodViewer.app"
  echo "     Codesign validation passed."

  # Prepare DMG layout
  echo "  -> Adding /Applications symlink..."
  ln -s /Applications "$staging_dir/Applications"

  # Create DMG
  echo "  -> Creating DMG with hdiutil..."
  rm -f "$dmg_out"
  hdiutil create -volname "超好读 SuperGoodViewer" \
    -srcfolder "$staging_dir" \
    -ov -format UDZO \
    "$dmg_out"

  # Cleanup staging
  rm -rf "$staging_dir"

  echo "==> DMG successfully created: $dmg_out"
  ls -lh "$dmg_out"
  echo ""
}

case "$TARGET_MODE" in
  universal)
    package_universal
    ;;
  arm64)
    package_arch "arm64"
    ;;
  x64|x86_64)
    package_arch "x64"
    ;;
  all)
    package_arch "arm64"
    package_arch "x64"
    ;;
  all-with-universal)
    package_universal
    package_arch "arm64"
    package_arch "x64"
    ;;
  *)
    echo "::error::Invalid target mode: $TARGET_MODE (expected 'universal', 'arm64', 'x64', 'all', or 'all-with-universal')"
    exit 1
    ;;
esac

echo "==> All requested macOS packages successfully built in $OUTPUT_DIR!"
