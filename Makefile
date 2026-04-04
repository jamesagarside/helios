# Helios GCS — Development Makefile
# Usage: make <target>

.DEFAULT_GOAL := help
SHELL := /bin/bash

# Load local secrets from .env if it exists (never committed)
-include .env
export APPLE_API_KEY APPLE_API_KEY_ID APPLE_API_ISSUER_ID

# ── Development ──────────────────────────────────────────────

.PHONY: run run-macos run-linux run-windows run-android run-ios
run: run-macos ## Run on default platform (macOS)

run-macos: ## Run debug on macOS
	flutter run -d macos

run-linux: ## Run debug on Linux
	flutter run -d linux

run-windows: ## Run debug on Windows
	flutter run -d windows

run-android: ## Run debug on connected Android device
	flutter run -d android

run-ios: ## Run debug on connected iOS device
	flutter run -d ios

run-ios-sim: ## Run debug on iOS Simulator (picks booted sim or launches one)
	@SIMID=$$(xcrun simctl list devices booted -j \
		| python3 -c "import sys,json; d=json.load(sys.stdin)['devices']; \
		  devs=[v for vals in d.values() for v in vals if v['state']=='Booted']; \
		  print(devs[0]['udid'] if devs else '')"); \
	if [ -z "$$SIMID" ]; then \
		echo "No booted simulator — launching iPhone 16..."; \
		xcrun simctl boot "iPhone 16" 2>/dev/null || true; \
		open -a Simulator; \
	fi; \
	flutter run -d "$(or $(SIM),iPhone 16)"

run-android-emu: ## Run debug on Android Emulator (launches if not running)
	@if ! flutter devices | grep -q emulator; then \
		EMU=$$(emulator -list-avds | head -1); \
		test -n "$$EMU" || (echo "No AVD found. Create one in Android Studio → Device Manager."; exit 1); \
		echo "Starting emulator: $$EMU"; \
		emulator -avd "$$EMU" -no-audio &\
		echo "Waiting for emulator to boot..."; \
		adb wait-for-device; \
		sleep 5; \
	fi; \
	flutter run -d emulator

run-sim: ## Run basic telemetry simulator (no SITL needed)
	dart run scripts/sim_telemetry.dart

run-sim-full: install-sim-deps ## Run full simulator (telemetry + video)
	@echo "Starting telemetry simulator..."
	@dart run scripts/sim_full.dart &
	@sleep 2
	@echo "Starting video stream (rtsp://127.0.0.1:8554/stream)..."
	@./scripts/sim_video.sh

run-sim-telem: ## Run telemetry simulator only (no video)
	dart run scripts/sim_full.dart

run-sim-multi: ## Run full simulator with 2 vehicles
	dart run scripts/sim_full.dart --multi

install-sim-deps: ## Install simulation dependencies (ffmpeg, mediamtx)
	@command -v ffmpeg >/dev/null 2>&1 || brew install ffmpeg
	@command -v mediamtx >/dev/null 2>&1 || brew install mediamtx

run-sim-video: install-sim-deps ## Stream test pattern video via RTSP
	./scripts/sim_video.sh

run-relay: ## Run WebSocket↔TCP relay for web browser connections
	dart run scripts/helios_relay.dart $(RELAY_ARGS)

build-relay: ## Compile relay to standalone binary (no Dart SDK needed to run)
	dart compile exe scripts/helios_relay.dart -o build/helios-relay
	@echo "Binary: build/helios-relay"

# ── Device testing (release builds on real hardware) ─────────

.PHONY: install-ios install-android devices

devices: ## List connected devices and simulators
	flutter devices

install-ios: ## Build + install release IPA on connected iPhone (no App Store needed)
	@flutter devices | grep -q "ios" || (echo "No iOS device connected. Connect via USB and trust this Mac."; exit 1)
	flutter run --release -d "$(shell flutter devices | grep "ios" | awk -F'•' '{print $$2}' | head -1 | xargs)"

install-android: ## Build + install release APK on connected Android device
	@flutter devices | grep -q "android" || (echo "No Android device connected. Enable USB debugging in Developer Options."; exit 1)
	flutter run --release -d "$(shell flutter devices | grep "android" | awk -F'•' '{print $$2}' | head -1 | xargs)"

install-android-apk: build-android ## Build APK and push directly via adb (bypasses Flutter runner)
	adb install -r build/app/outputs/flutter-apk/app-release.apk
	@echo "Installed. Launch Helios GCS on your device."

# ── Testing ──────────────────────────────────────────────────

.PHONY: test analyze lint check
test: ## Run all Flutter tests
	flutter test

analyze: ## Run Dart analyzer with fatal warnings (matches CI exactly)
	@for dir in packages/*/; do \
		if [ -f "$$dir/pubspec.yaml" ]; then \
			echo "pub get $$dir"; \
			(cd "$$dir" && dart pub get); \
		fi; \
	done
	dart analyze --fatal-warnings lib/ test/ packages/dart_mavlink/

lint: analyze ## Alias for analyze

check: analyze test ## Run analyzer + tests (CI equivalent)
	@echo "All checks passed."

# ── Building ─────────────────────────────────────────────────

.PHONY: build-macos build-linux build-windows build-android build-ios build-web build-all build-check

build-macos: ## Build macOS release
	flutter build macos --release

build-linux: ## Build Linux release
	flutter build linux --release

build-windows: ## Build Windows release
	flutter build windows --release

build-android: ## Build Android APK + AAB
	flutter build apk --release
	flutter build appbundle --release

build-ios: ## Build iOS (unsigned)
	flutter build ios --release --no-codesign

build-web: ## Build web release
	flutter build web --release

build-all: build-macos build-linux build-windows build-android build-ios ## Build all platforms

build-check: ## Compile-check all platforms available on this Mac (no signing)
	@echo "══════════════════════════════════════════════"
	@echo " Helios Build Check — all local platforms"
	@echo "══════════════════════════════════════════════"
	@PASS=0; FAIL=0; RESULTS=""; \
	for platform in macos ios android web; do \
		case $$platform in \
			macos)   CMD="flutter build macos --release" ;; \
			ios)     CMD="flutter build ios --release --no-codesign" ;; \
			android) CMD="flutter build apk --release" ;; \
			web)     CMD="flutter build web --release" ;; \
		esac; \
		echo ""; \
		echo "── $$platform ──────────────────────────────"; \
		if $$CMD 2>&1; then \
			PASS=$$((PASS + 1)); \
			RESULTS="$$RESULTS  ✓ $$platform\n"; \
		else \
			FAIL=$$((FAIL + 1)); \
			RESULTS="$$RESULTS  ✗ $$platform\n"; \
		fi; \
	done; \
	echo ""; \
	echo "══════════════════════════════════════════════"; \
	printf " Results:\n$$RESULTS"; \
	echo " $$PASS passed, $$FAIL failed"; \
	echo "══════════════════════════════════════════════"; \
	test $$FAIL -eq 0

# ── Packaging ────────────────────────────────────────────────

.PHONY: package-macos package-linux package-windows

package-macos: build-macos ## Create macOS .dmg
	@cd build/macos/Build/Products/Release && \
		mkdir -p dmg_contents && \
		cp -R helios_gcs.app dmg_contents/ && \
		ln -sf /Applications dmg_contents/Applications && \
		hdiutil create -volname "Helios GCS" -srcfolder dmg_contents -ov -format UDZO ../helios-gcs-macos.dmg && \
		rm -rf dmg_contents
	@echo "DMG: build/macos/Build/Products/helios-gcs-macos.dmg"

package-linux: build-linux ## Create Linux tarball
	@cd build/linux/x64/release/bundle && \
		tar czf ../../../helios-gcs-linux-x64.tar.gz .
	@echo "Tarball: build/linux/x64/release/helios-gcs-linux-x64.tar.gz"

package-linux-appimage: build-linux ## Create Linux AppImage installer
	./packaging/linux/build_appimage.sh
	@echo "AppImage: build/helios-gcs-linux-x64.AppImage"

package-windows: build-windows ## Create Windows zip
	@cd build/windows/x64/runner/Release && \
		zip -r ../../../../helios-gcs-windows-x64.zip .
	@echo "Zip: build/helios-gcs-windows-x64.zip"

package-windows-installer: build-windows ## Create Windows installer (requires Inno Setup)
	iscc packaging/windows/inno_setup.iss
	@echo "Installer: build/helios-gcs-windows-x64-setup.exe"

# ── Website ─────────────────────────────────────────────────

.PHONY: serve-website

serve-website: ## Serve the website locally at http://localhost:8000
	@echo "Serving website at http://localhost:8000"
	@cd website && python3 -m http.server 8000

# ── Code Generation ──────────────────────────────────────────

.PHONY: gen-crc gen-all

gen-crc: ## Regenerate MAVLink CRC extras from XML definitions
	dart run scripts/generate_crc_extras.dart

gen-all: gen-crc ## Run all code generators

# ── Dependencies ─────────────────────────────────────────────

.PHONY: deps deps-upgrade outdated

deps: ## Get all dependencies
	flutter pub get

deps-upgrade: ## Upgrade dependencies (within constraints)
	flutter pub upgrade

outdated: ## Show outdated packages
	flutter pub outdated

# ── SITL ─────────────────────────────────────────────────────

.PHONY: sitl

sitl: ## Download (if needed) and launch ArduPilot SITL natively
	@echo "Use the Simulate tab in Helios for the full experience."
	@echo "Or launch directly: dart run scripts/sim_telemetry.dart"

# ── Cleanup ──────────────────────────────────────────────────

.PHONY: clean clean-all

clean: ## Clean Flutter build artifacts
	flutter clean

clean-all: clean ## Deep clean (build + pods + generated)
	rm -rf build/ macos/Pods/ macos/Podfile.lock
	rm -rf .dart_tool/ .packages
	flutter pub get

# ── Signing (local, no push needed) ──────────────────────────

.PHONY: sign-macos notarize-macos package-ios

sign-macos: build-macos ## Build + sign macOS app with local Developer ID cert
	$(eval IDENTITY := $(shell security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $$2}'))
	@test -n "$(IDENTITY)" || (echo "No Developer ID Application cert found in keychain"; exit 1)
	@echo "Signing with identity: $(IDENTITY)"
	$(MAKE) _codesign-app IDENTITY="$(IDENTITY)"
	@echo "Signed. Run 'make notarize-macos' to notarize."

# Sign all nested frameworks first (inside-out), then the app bundle.
# --deep is unreliable for Versions/A/ framework structures; this is the correct approach.
_codesign-app:
	$(eval APP := build/macos/Build/Products/Release/helios_gcs.app)
	@echo "Signing nested frameworks..."
	@find "$(APP)/Contents/Frameworks" \( -name "*.framework" -o -name "*.dylib" \) \
		| sort -r \
		| while read f; do \
			codesign --force --options runtime --timestamp \
				--entitlements macos/Runner/Release.entitlements \
				--sign "$(IDENTITY)" "$$f" || exit 1; \
		done
	@echo "Signing app bundle..."
	codesign --force --options runtime --timestamp \
		--entitlements macos/Runner/Release.entitlements \
		--sign "$(IDENTITY)" \
		"$(APP)"

notarize-macos: ## Build, sign, notarize + staple macOS DMG (reads APPLE_API_KEY* from .env)
	@test -n "$(APPLE_API_KEY)" || (echo "Error: APPLE_API_KEY not set in .env"; exit 1)
	@test -n "$(APPLE_API_KEY_ID)" || (echo "Error: APPLE_API_KEY_ID not set in .env"; exit 1)
	@test -n "$(APPLE_API_ISSUER_ID)" || (echo "Error: APPLE_API_ISSUER_ID not set in .env"; exit 1)
	$(eval IDENTITY := $(shell security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $$2}'))
	$(MAKE) build-macos
	$(MAKE) _codesign-app IDENTITY="$(IDENTITY)"
	$(MAKE) _package-dmg IDENTITY="$(IDENTITY)"
	xcrun notarytool submit build/macos/Build/Products/helios-gcs-macos.dmg \
		--key "$(APPLE_API_KEY)" \
		--key-id "$(APPLE_API_KEY_ID)" \
		--issuer "$(APPLE_API_ISSUER_ID)" \
		--wait
	xcrun stapler staple build/macos/Build/Products/helios-gcs-macos.dmg
	@echo "Done: build/macos/Build/Products/helios-gcs-macos.dmg"

_package-dmg:
	cd build/macos/Build/Products/Release && \
		rm -rf dmg_contents && mkdir -p dmg_contents && \
		cp -R helios_gcs.app dmg_contents/ && \
		ln -sf /Applications dmg_contents/Applications && \
		hdiutil create -volname "Helios GCS" -srcfolder dmg_contents -ov -format UDZO ../helios-gcs-macos.dmg && \
		rm -rf dmg_contents
	codesign --force --timestamp --sign "$(IDENTITY)" \
		build/macos/Build/Products/helios-gcs-macos.dmg

package-ios: ## Build signed IPA locally (requires cert + profile installed)
	flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
	@echo "IPA: build/ios/ipa/"

# ── Release ──────────────────────────────────────────────────

.PHONY: release

release: ## Tag a release (usage: make release V=0.2.0)
ifndef V
	$(error Set version: make release V=0.2.0)
endif
	@echo "Tagging v$(V)..."
	git tag -a v$(V) -m "Release v$(V)"
	git push origin v$(V)
	@echo "Release v$(V) tagged. GitHub Actions will build and publish."

# ── Help ─────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
