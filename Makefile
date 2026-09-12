.PHONY: all build build-core build-app test test-core test-app clean run-macos dmg

all: build test

# Build Rust dynamic library and Flutter Desktop app
build: build-core build-app
	@echo "==> Packaging dylib into macOS App Bundle..."
	@mkdir -p ui/build/macos/Build/Products/Release/sogoodviewer.app/Contents/Frameworks/
	@cp core/target/release/libsogood_core.dylib ui/build/macos/Build/Products/Release/sogoodviewer.app/Contents/Frameworks/
	@echo "==> Build complete! Output: ui/build/macos/Build/Products/Release/sogoodviewer.app"

build-core:
	@echo "==> Building Rust sogood_core (release)..."
	@cd core && cargo build --release

build-app:
	@echo "==> Building Flutter Desktop macOS app..."
	@cd ui && flutter build macos

# Run all test suites across Rust core and Flutter UI
test: test-core build-core test-app
	@echo "==> All test suites passed with 0 errors!"

test-core:
	@echo "==> Running Rust core unit & integration tests..."
	@cd core && cargo test -- --nocapture

test-app:
	@echo "==> Running Flutter static analysis and tests..."
	@cd ui && flutter analyze
	@cd ui && flutter test

run-macos: build-core
	@echo "==> Launching SuperGoodViewer in dev mode..."
	@cd ui && flutter run -d macos

clean:
	@echo "==> Cleaning artifacts..."
	@cd core && cargo clean
	@cd ui && flutter clean

dmg: build
	@echo "==> Creating macOS DMG..."
	@hdiutil create -volname "SuperGoodViewer" \
		-srcfolder "ui/build/macos/Build/Products/Release/sogoodviewer.app" \
		-ov -format UDZO \
		"SuperGoodViewer-macos.dmg"
	@echo "==> DMG generated: SuperGoodViewer-macos.dmg"
