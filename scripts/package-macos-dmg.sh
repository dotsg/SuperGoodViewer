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
  echo "Please build the macOS app first (e.g. 'make build', 'make build-universal', or 'flutter build macos --release')."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

verify_component_arch() {
  local staging_dir="$1"
  local target_arch="$2"
  local rel_path="$3"
  local full_path="$staging_dir/SuperGoodViewer.app/$rel_path"
  if [ ! -f "$full_path" ]; then
    echo "::error::Required component missing: $rel_path"
    exit 1
  fi
  local actual_arch
  actual_arch=$(lipo -archs "$full_path")
  if [ "$actual_arch" != "$target_arch" ]; then
    echo "::error::$rel_path architecture is '$actual_arch', expected '$target_arch'"
    echo "Hint: If you previously built with a single-arch target, run 'make build-universal' first."
    exit 1
  fi
  echo "     Verified: $rel_path architecture = $actual_arch"
}

verify_universal_component() {
  local staging_dir="$1"
  local rel_path="$2"
  local full_path="$staging_dir/SuperGoodViewer.app/$rel_path"
  if [ ! -f "$full_path" ]; then
    echo "::error::Required component missing: $rel_path"
    exit 1
  fi
  local actual_arch
  actual_arch=$(lipo -archs "$full_path")
  echo "$actual_arch" | grep -qw arm64 || { echo "::error::$rel_path missing arm64 slice"; exit 1; }
  echo "$actual_arch" | grep -qw x86_64 || { echo "::error::$rel_path missing x86_64 slice"; exit 1; }
  echo "     Verified universal: $rel_path ($actual_arch)"
}

package_universal() {
  local dmg_filename=""
  if [ -n "$VERSION_TAG" ]; then
    dmg_filename="SuperGoodViewer-${VERSION_TAG}-macos.dmg"
  else
    dmg_filename="SuperGoodViewer-macos.dmg"
  fi

  local dmg_out="$OUTPUT_DIR/$dmg_filename"
  local staging_dir="$ROOT_DIR/build/dmg-staging-universal"
  trap 'rm -rf "$staging_dir"' EXIT

  echo "================================================================="
  echo "==> Packaging Universal macOS DMG (arm64 + x86_64)"
  echo "    Output DMG: $dmg_out"
  echo "================================================================="

  rm -rf "$staging_dir"
  mkdir -p "$staging_dir"

  echo "  -> Staging clean App Bundle copy..."
  cp -R "$SOURCE_APP" "$staging_dir/SuperGoodViewer.app"

  echo "  -> Verifying universal components..."
  verify_universal_component "$staging_dir" "Contents/MacOS/SuperGoodViewer"
  verify_universal_component "$staging_dir" "Contents/Frameworks/libsogood_core.dylib"
  verify_universal_component "$staging_dir" "Contents/Resources/bin/sgv-cli"

  if [ ! -x "$staging_dir/SuperGoodViewer.app/Contents/Resources/bin/sgv" ]; then
    echo "::error::Missing or non-executable CLI launcher: Contents/Resources/bin/sgv"
    exit 1
  fi
  echo "     Verified: Contents/Resources/bin/sgv is present and executable"

  # Re-signing
  echo "  -> Re-signing app bundle (ad-hoc)..."
  codesign --force --deep --sign - "$staging_dir/SuperGoodViewer.app"
  # --deep drops the entitlements Xcode applied, so re-apply them to the top-level bundle.
  codesign --force --sign - --entitlements "$ROOT_DIR/ui/macos/Runner/Release.entitlements" "$staging_dir/SuperGoodViewer.app"
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
  trap - EXIT

  echo "==> Universal DMG successfully created: $dmg_out"
  ls -lh "$dmg_out"
  echo ""
}

package_arch() {
  local arch_name="$1"      # "arm64" or "x64"
  local target_arch=""       # "arm64" or "x86_64" for lipo
  local volname_arch=""

  if [ "$arch_name" = "arm64" ] || [ "$arch_name" = "aarch64" ]; then
    arch_name="arm64"
    target_arch="arm64"
    volname_arch="Apple Silicon arm64"
  elif [ "$arch_name" = "x64" ] || [ "$arch_name" = "x86_64" ]; then
    arch_name="x64"
    target_arch="x86_64"
    volname_arch="Intel x64"
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
  trap 'rm -rf "$staging_dir"' EXIT

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
      if [ -z "$archs" ]; then
        echo "::warning::Could not read lipo architectures for Mach-O file: $file"
        continue
      fi
      if echo "$archs" | grep -qw "$target_arch"; then
        local count
        count=$(echo "$archs" | wc -w)
        if [ "$count" -gt 1 ]; then
          echo "     [lipo -thin] $(basename "$file") ($archs) -> $target_arch"
          lipo -thin "$target_arch" "$file" -output "$file"
          thinned_count=$((thinned_count + 1))
        fi
      else
        echo "::error::File $file does not contain target slice $target_arch (has: $archs)"
        echo "Hint: If you previously built with a single-arch target, run 'make build-universal' first."
        exit 1
      fi
    fi
  done < <(find "$staging_dir/SuperGoodViewer.app" -type f -print0)

  echo "  -> Thinned $thinned_count binary/library slices to $target_arch."

  echo "  -> Verifying required single-architecture components..."
  verify_component_arch "$staging_dir" "$target_arch" "Contents/MacOS/SuperGoodViewer"
  verify_component_arch "$staging_dir" "$target_arch" "Contents/Frameworks/libsogood_core.dylib"
  verify_component_arch "$staging_dir" "$target_arch" "Contents/Resources/bin/sgv-cli"

  if [ ! -x "$staging_dir/SuperGoodViewer.app/Contents/Resources/bin/sgv" ]; then
    echo "::error::Missing or non-executable CLI launcher: Contents/Resources/bin/sgv"
    exit 1
  fi
  echo "     Verified: Contents/Resources/bin/sgv is present and executable"

  # Re-signing
  echo "  -> Re-signing app bundle (ad-hoc)..."
  codesign --force --deep --sign - "$staging_dir/SuperGoodViewer.app"
  # --deep drops the entitlements Xcode applied, so re-apply them to the top-level bundle.
  codesign --force --sign - --entitlements "$ROOT_DIR/ui/macos/Runner/Release.entitlements" "$staging_dir/SuperGoodViewer.app"
  codesign --verify --deep --strict "$staging_dir/SuperGoodViewer.app"
  echo "     Codesign validation passed."

  # Prepare DMG layout
  echo "  -> Adding /Applications symlink..."
  ln -s /Applications "$staging_dir/Applications"

  # Create DMG
  echo "  -> Creating DMG with hdiutil..."
  rm -f "$dmg_out"
  hdiutil create -volname "超好读 SuperGoodViewer ($volname_arch)" \
    -srcfolder "$staging_dir" \
    -ov -format UDZO \
    "$dmg_out"

  # Cleanup staging
  rm -rf "$staging_dir"
  trap - EXIT

  echo "==> DMG successfully created: $dmg_out"
  ls -lh "$dmg_out"
  echo ""
}

case "$TARGET_MODE" in
  universal)
    package_universal
    ;;
  arm64|aarch64)
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
