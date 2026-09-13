ifeq ($(OS),Windows_NT)
  FLUTTER ?= flutter.bat
else
  FLUTTER ?= flutter
endif

.PHONY: all build build-core build-app build-windows build-windows-arm64 test test-core test-app bench benchmark clean run-macos run-windows dmg package-windows package-windows-arm64

all: build test

# Build Rust dynamic library and Flutter Desktop app
build: build-core build-app
	@echo "==> Packaging dylib into macOS App Bundle..."
	@mkdir -p ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Frameworks/
	@cp core/target/release/libsogood_core.dylib ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Frameworks/
	@echo "==> Packaging CLI script into macOS App Bundle..."
	@mkdir -p ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Resources/bin/
	@cp ui/bin/sgv ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Resources/bin/sgv
	@chmod +x ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Resources/bin/sgv
	@echo "==> Build complete! Output: ui/build/macos/Build/Products/Release/SuperGoodViewer.app"

build-core:
	@echo "==> Building Rust sogood_core (release)..."
	@cd core && cargo build --release --lib

build-app:
	@echo "==> Building Flutter Desktop macOS app..."
	@cd ui && $(FLUTTER) build macos

# Run all test suites across Rust core and Flutter UI
test: test-core build-core test-app
	@echo "==> All test suites passed with 0 errors!"

test-core:
	@echo "==> Running Rust core unit & integration tests..."
	@cd core && cargo test --lib -- --nocapture

test-app:
	@echo "==> Running Flutter static analysis and tests..."
	@cd ui && $(FLUTTER) analyze
	@cd ui && $(FLUTTER) test

# Run micro-benchmarks explicitly on demand
benchmark: bench
bench:
	@echo "==> Running SuperGoodViewer Rust Core Micro-Benchmarks..."
	@cd core && cargo run --release --bin benchmark

run-macos: build-core
	@echo "==> Launching SuperGoodViewer in dev mode (macOS)..."
	@cd ui && $(FLUTTER) run -d macos

build-windows: build-core
	@echo "==> Building Flutter Desktop Windows app..."
	@cd ui && $(FLUTTER) build windows --release
	@echo "==> Injecting Rust DLL & CLI script into Windows bundle..."
	@mkdir -p ui/build/windows/x64/runner/Release
	@cp core/target/release/sogood_core.dll ui/build/windows/x64/runner/Release/
	@cp ui/bin/sgv.cmd ui/build/windows/x64/runner/Release/
	@cp ui/bin/sgv.ps1 ui/build/windows/x64/runner/Release/
	@echo "==> Windows build complete! Output: ui/build/windows/x64/runner/Release/"

run-windows: build-core
	@echo "==> Launching SuperGoodViewer in dev mode (Windows)..."
	@mkdir -p ui/build/windows/x64/runner/Debug
	@cp core/target/release/sogood_core.dll ui/build/windows/x64/runner/Debug/ 2>/dev/null || true
	@cd ui && $(FLUTTER) run -d windows

clean:
	@echo "==> Cleaning artifacts..."
	@cd core && cargo clean
	@cd ui && $(FLUTTER) clean

package-windows: build-windows
	@echo "==> Packaging Windows portable release..."
	@powershell -Command "New-Item -ItemType Directory -Force -Path dist; Compress-Archive -Force -Path 'ui/build/windows/x64/runner/Release/*' -DestinationPath 'dist/SuperGoodViewer-windows-x64.zip'"
	@echo "==> Package created: dist/SuperGoodViewer-windows-x64.zip"

build-windows-arm64:
	@echo "==> Building Rust sogood_core for aarch64-pc-windows-msvc..."
	@cd core && cargo build --release --lib --target aarch64-pc-windows-msvc
	@echo "==> Configuring and building Flutter Windows ARM64 target..."
	@cd ui && $(FLUTTER) build windows --config-only
	@cmake -S ui/windows -B ui/build/windows_arm64 -A ARM64 -DFLUTTER_TARGET_PLATFORM=windows-arm64
	@cmake --build ui/build/windows_arm64 --config Release --target INSTALL
	@echo "==> Injecting Rust ARM64 DLL & CLI scripts into Windows ARM64 bundle..."
	@cp core/target/aarch64-pc-windows-msvc/release/sogood_core.dll ui/build/windows_arm64/runner/Release/
	@cp ui/bin/sgv.cmd ui/build/windows_arm64/runner/Release/
	@cp ui/bin/sgv.ps1 ui/build/windows_arm64/runner/Release/
	@echo "==> Windows ARM64 build complete! Output: ui/build/windows_arm64/runner/Release/"

package-windows-arm64: build-windows-arm64
	@echo "==> Packaging Windows ARM64 portable release..."
	@powershell -Command "New-Item -ItemType Directory -Force -Path dist; Compress-Archive -Force -Path 'ui/build/windows_arm64/runner/Release/*' -DestinationPath 'dist/SuperGoodViewer-windows-arm64.zip'"
	@echo "==> Package created: dist/SuperGoodViewer-windows-arm64.zip"

dmg: build
	@echo "==> Preparing macOS DMG staging folder..."
	@rm -rf build/dmg-staging
	@mkdir -p build/dmg-staging
	@cp -R "ui/build/macos/Build/Products/Release/SuperGoodViewer.app" build/dmg-staging/SuperGoodViewer.app
	@ln -s /Applications build/dmg-staging/Applications
	@echo "==> Creating macOS DMG..."
	@hdiutil create -volname "超好读 SuperGoodViewer" \
		-srcfolder "build/dmg-staging" \
		-ov -format UDZO \
		"SuperGoodViewer-macos.dmg"
	@rm -rf build/dmg-staging
	@echo "==> DMG generated: SuperGoodViewer-macos.dmg"


