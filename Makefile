# Helios GCS — Development Makefile
# Usage: make <target>

.DEFAULT_GOAL := help
SHELL := /bin/bash

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

run-sim: ## Run Dart telemetry simulator (no SITL needed)
	dart run scripts/sim_telemetry.dart

# ── Testing ──────────────────────────────────────────────────

.PHONY: test analyze lint check
test: ## Run all Flutter tests
	flutter test

analyze: ## Run Dart analyzer with fatal warnings
	dart analyze --fatal-warnings lib/ test/ packages/dart_mavlink/

lint: analyze ## Alias for analyze

check: analyze test ## Run analyzer + tests (CI equivalent)
	@echo "All checks passed."

# ── Building ─────────────────────────────────────────────────

.PHONY: build-macos build-linux build-windows build-android build-ios build-all

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

build-all: build-macos build-linux build-windows build-android build-ios ## Build all platforms

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

package-windows: build-windows ## Create Windows zip
	@cd build/windows/x64/runner/Release && \
		zip -r ../../../../helios-gcs-windows-x64.zip .
	@echo "Zip: build/helios-gcs-windows-x64.zip"

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

.PHONY: sitl sitl-stop

sitl: ## Start ArduPilot SITL in Docker (TCP 5760)
	docker run -d --name helios-sitl \
		-p 5760:5760 \
		radarku/ardupilot-sitl \
		/ardupilot/build/sitl/bin/arduplane \
		--model plane \
		--home -35.3632,149.1652,584,0 \
		--defaults /ardupilot/Tools/autotest/default_params/plane.parm
	@echo "SITL running. Connect via TCP 127.0.0.1:5760"

sitl-stop: ## Stop SITL Docker container
	docker stop helios-sitl && docker rm helios-sitl

# ── Cleanup ──────────────────────────────────────────────────

.PHONY: clean clean-all

clean: ## Clean Flutter build artifacts
	flutter clean

clean-all: clean ## Deep clean (build + pods + generated)
	rm -rf build/ macos/Pods/ macos/Podfile.lock
	rm -rf .dart_tool/ .packages
	flutter pub get

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
