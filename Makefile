ifeq ($(OS),Windows_NT)
  FLUTTER ?= flutter.bat
else
  FLUTTER ?= flutter
endif

.PHONY: all build build-universal build-core build-core-universal build-app build-windows build-windows-arm64 build-linux test test-core test-app test-release-local bench bench-json benchmark clean run-macos run-windows run-linux dmg dmg-arm64 dmg-x64 package-windows package-windows-arm64 package-linux

all: build test

# Build Rust dynamic library and Flutter Desktop app (host architecture -- fast path for local development)
build: build-core build-app
	@echo "==> Packaging host dylib into macOS App Bundle..."
	@mkdir -p ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Frameworks/
	@cp core/target/release/libsogood_core.dylib ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Frameworks/
	@echo "==> Packaging CLI scripts and tools into macOS App Bundle..."
	@mkdir -p ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Resources/bin/
	@cp ui/bin/sgv ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Resources/bin/sgv
	@cp core/target/release/sgv-cli ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Resources/bin/sgv-cli
	@chmod +x ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Resources/bin/sgv
	@chmod +x ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Resources/bin/sgv-cli
	@echo "==> Re-signing macOS App Bundle..."
	@codesign --force --deep --sign - ui/build/macos/Build/Products/Release/SuperGoodViewer.app
	@echo "==> Build complete! Output: ui/build/macos/Build/Products/Release/SuperGoodViewer.app"

# Full universal (arm64 + x86_64) binaries for macOS release distribution
build-universal: build-core-universal build-app
	@echo "==> Packaging universal dylib into macOS App Bundle..."
	@mkdir -p ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Frameworks/
	@cp core/target/universal/release/libsogood_core.dylib ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Frameworks/
	@echo "==> Packaging CLI scripts and tools into macOS App Bundle..."
	@mkdir -p ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Resources/bin/
	@cp ui/bin/sgv ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Resources/bin/sgv
	@cp core/target/universal/release/sgv-cli ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Resources/bin/sgv-cli
	@chmod +x ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Resources/bin/sgv
	@chmod +x ui/build/macos/Build/Products/Release/SuperGoodViewer.app/Contents/Resources/bin/sgv-cli
	@echo "==> Re-signing macOS App Bundle..."
	@codesign --force --deep --sign - ui/build/macos/Build/Products/Release/SuperGoodViewer.app
	@echo "==> Universal build complete! Output: ui/build/macos/Build/Products/Release/SuperGoodViewer.app"

# Host-architecture only -- fast path for local development (run-macos, tests).
build-core:
	@echo "==> Building Rust sogood_core & sgv-cli (release, host arch)..."
	@cd core && cargo build --release --lib
	@cd core && cargo build --release -p sgv-cli

# Universal (arm64 + x86_64) binaries. Flutter emits a universal Runner/engine for
# release macOS builds, so an arm64-only dylib makes dlopen fail on Intel Macs
# with "Invalid arguments" (incompatible architecture).
build-core-universal:
	@echo "==> Building Rust sogood_core & sgv-cli (release, arm64 + x86_64)..."
	@rustup target add aarch64-apple-darwin x86_64-apple-darwin
	@cd core && cargo build --release --lib --target aarch64-apple-darwin
	@cd core && cargo build --release -p sgv-cli --target aarch64-apple-darwin
	@cd core && cargo build --release --lib --target x86_64-apple-darwin
	@cd core && cargo build --release -p sgv-cli --target x86_64-apple-darwin
	@echo "==> Merging into universal binaries with lipo..."
	@mkdir -p core/target/universal/release
	@lipo -create \
		core/target/aarch64-apple-darwin/release/libsogood_core.dylib \
		core/target/x86_64-apple-darwin/release/libsogood_core.dylib \
		-output core/target/universal/release/libsogood_core.dylib
	@lipo -create \
		core/target/aarch64-apple-darwin/release/sgv-cli \
		core/target/x86_64-apple-darwin/release/sgv-cli \
		-output core/target/universal/release/sgv-cli
	@lipo -info core/target/universal/release/libsogood_core.dylib
	@lipo -info core/target/universal/release/sgv-cli

build-app:
	@echo "==> Building Flutter Desktop macOS app..."
	@cd ui && $(FLUTTER) build macos

# Run all test suites across Rust core and Flutter UI
test: test-core build-core test-app
	@echo "==> All test suites passed with 0 errors!"

test-core:
	@echo "==> Running Rust core unit & integration tests..."
	@cd core && cargo test --lib -- --nocapture
	@cd core && cargo test -p sgv-cli -- --nocapture

test-app:
	@echo "==> Running Flutter static analysis and tests..."
	@cd ui && $(FLUTTER) analyze
	@cd ui && $(FLUTTER) test

test-release-local:
	@echo "==> Running local release rehearsal simulation (Windows x64 + Linux x64)..."
	@powershell -ExecutionPolicy Bypass -File scripts/test-release-local.ps1

# Run micro-benchmarks explicitly on demand
benchmark: bench
bench:
	@echo "==> Running SuperGoodViewer Rust Core Micro-Benchmarks..."
	@cd core && cargo run --release --bin benchmark

# Same suite, also refreshing the machine-readable results committed under docs/
bench-json:
	@echo "==> Running benchmarks and refreshing docs/benchmark-results.json..."
	@cd core && cargo run --release --bin benchmark -- --json ../docs/benchmark-results.json

run-macos: build-core
	@echo "==> Launching SuperGoodViewer in dev mode (macOS)..."
	@cd ui && $(FLUTTER) run -d macos

build-windows: build-core
	@echo "==> Building Flutter Desktop Windows app..."
	@cd ui && $(FLUTTER) build windows --release
	@echo "==> Injecting Rust DLL & CLI script into Windows bundle..."
	@mkdir -p ui/build/windows/x64/runner/Release
	@cp core/target/release/sogood_core.dll ui/build/windows/x64/runner/Release/
	@cp core/target/release/sgv-cli.exe ui/build/windows/x64/runner/Release/
	@cp ui/bin/sgv.cmd ui/build/windows/x64/runner/Release/
	@cp ui/bin/sgv.ps1 ui/build/windows/x64/runner/Release/
	@echo "==> Windows build complete! Output: ui/build/windows/x64/runner/Release/"

run-windows: build-core
	@echo "==> Launching SuperGoodViewer in dev mode (Windows)..."
	@mkdir -p ui/build/windows/x64/runner/Debug
	@cp core/target/release/sogood_core.dll ui/build/windows/x64/runner/Debug/ 2>/dev/null || true
	@cd ui && $(FLUTTER) run -d windows

build-linux: build-core
	@echo "==> Building Flutter Desktop Linux app..."
	@cd ui && $(FLUTTER) build linux --release
	@echo "==> Injecting CLI tools into Linux bundle..."
	@mkdir -p ui/build/linux/x64/release/bundle/bin
	@cp core/target/release/sgv-cli ui/build/linux/x64/release/bundle/bin/
	@chmod +x ui/build/linux/x64/release/bundle/bin/sgv-cli
	@echo "==> Linux build complete! Output: ui/build/linux/x64/release/bundle/"

run-linux: build-core
	@echo "==> Launching SuperGoodViewer in dev mode (Linux)..."
	@mkdir -p ui/build/linux/x64/debug/bundle/lib
	@cp core/target/release/libsogood_core.so ui/build/linux/x64/debug/bundle/lib/ 2>/dev/null || true
	@cd ui && $(FLUTTER) run -d linux

package-linux: build-linux
	@echo "==> Packaging Linux portable release..."
	@mkdir -p dist
	@tar -czvf dist/SuperGoodViewer-linux-x64.tar.gz -C ui/build/linux/x64/release/bundle .
	@echo "==> Package created: dist/SuperGoodViewer-linux-x64.tar.gz"

clean:
	@echo "==> Cleaning artifacts..."
	@cd core && cargo clean
	@cd ui && $(FLUTTER) clean

package-windows: build-windows
	@echo "==> Packaging Windows portable release..."
	@powershell -Command "New-Item -ItemType Directory -Force -Path dist; Compress-Archive -Force -Path 'ui/build/windows/x64/runner/Release/*' -DestinationPath 'dist/SuperGoodViewer-windows-x64.zip'"
	@echo "==> Package created: dist/SuperGoodViewer-windows-x64.zip"

build-windows-arm64:
	@echo "==> Building Rust sogood_core & sgv-cli for aarch64-pc-windows-msvc..."
	@cd core && cargo build --release --lib --target aarch64-pc-windows-msvc
	@cd core && cargo build --release -p sgv-cli --target aarch64-pc-windows-msvc
	@echo "==> Configuring and building Flutter Windows ARM64 target..."
	@cd ui && $(FLUTTER) build windows --config-only
	@cmake -S ui/windows -B ui/build/windows_arm64 -A ARM64 -DFLUTTER_TARGET_PLATFORM=windows-arm64 -DCMAKE_DISABLE_FIND_PACKAGE_JNI=TRUE
	@cmake --build ui/build/windows_arm64 --config Release --target INSTALL
	@echo "==> Injecting Rust ARM64 DLL & CLI scripts into Windows ARM64 bundle..."
	@cp core/target/aarch64-pc-windows-msvc/release/sogood_core.dll ui/build/windows_arm64/runner/Release/
	@cp core/target/aarch64-pc-windows-msvc/release/sgv-cli.exe ui/build/windows_arm64/runner/Release/
	@cp ui/bin/sgv.cmd ui/build/windows_arm64/runner/Release/
	@cp ui/bin/sgv.ps1 ui/build/windows_arm64/runner/Release/
	@echo "==> Windows ARM64 build complete! Output: ui/build/windows_arm64/runner/Release/"

package-windows-arm64: build-windows-arm64
	@echo "==> Packaging Windows ARM64 portable release..."
	@powershell -Command "New-Item -ItemType Directory -Force -Path dist; Compress-Archive -Force -Path 'ui/build/windows_arm64/runner/Release/*' -DestinationPath 'dist/SuperGoodViewer-windows-arm64.zip'"
	@echo "==> Package created: dist/SuperGoodViewer-windows-arm64.zip"

dmg: build-universal
	@echo "==> Packaging Universal macOS DMG..."
	@./scripts/package-macos-dmg.sh universal dist

dmg-arm64: build
	@echo "==> Packaging Apple Silicon (arm64) macOS DMG..."
	@./scripts/package-macos-dmg.sh arm64 dist

dmg-x64: build-universal
	@echo "==> Packaging Intel (x64) macOS DMG..."
	@./scripts/package-macos-dmg.sh x64 dist


