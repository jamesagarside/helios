# Building from Source

This guide covers setting up a development environment and building Helios from source on each supported platform.

---

## Prerequisites

### macOS

| Requirement | Version | Install |
|---|---|---|
| Xcode | 15+ | Mac App Store or `xcode-select --install` |
| Flutter | 3.38+ | [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install) |
| CocoaPods | Latest | `sudo gem install cocoapods` |

### Linux

| Requirement | Install |
|---|---|
| Flutter 3.38+ | [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install) |
| clang | `sudo apt install clang` |
| cmake | `sudo apt install cmake` |
| ninja-build | `sudo apt install ninja-build` |
| GTK3 dev headers | `sudo apt install libgtk-3-dev` |
| pkg-config | `sudo apt install pkg-config` |
| libudev | `sudo apt install libudev-dev` (for serial port support) |

### Windows

| Requirement | Install |
|---|---|
| Flutter 3.38+ | [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install) |
| Visual Studio 2022 | With **Desktop development with C++** workload |

---

## Clone and Install Dependencies

```bash
git clone https://github.com/jamesagarside/helios.git
cd helios
flutter pub get
```

---

## DuckDB Native Library

Helios requires the DuckDB native library at runtime. See the [Installation guide](installation.md) for platform-specific instructions on placing the DuckDB library.

---

## Build and Test Commands

Helios uses a Makefile for common development tasks:

| Command | Description |
|---|---|
| `make check` | Run static analysis and all tests. **Run this before every commit.** |
| `make run` | Build and run on macOS (debug). |
| `make run-linux` | Build and run on Linux (debug). |
| `make build-macos` | Create a release build for macOS. |
| `make build-linux` | Create a release build for Linux. |
| `make build-windows` | Create a release build for Windows. |
| `make package-macos` | Create a `.dmg` installer for macOS. |
| `make package-linux` | Create a Linux `.tar.gz` tarball. |
| `make package-windows` | Create a Windows `.zip` archive. |
| `make gen-crc` | Regenerate MAVLink CRC extras from XML definitions. |
| `make sitl` | Launch ArduPilot SITL for testing. |
| `make clean` | Clean Flutter build artifacts. |
| `make clean-all` | Deep clean (build, pods, generated files). |

### Without Make

If `make` is not available, use the Flutter and Dart CLI directly:

```bash
dart analyze --fatal-warnings lib/ test/ packages/dart_mavlink/
flutter test
flutter run -d macos
```

Replace `-d macos` with `-d linux` or `-d windows` as needed.

---

## Release Builds

### macOS

```bash
make build-macos      # Produces .app bundle
make package-macos    # Produces .dmg installer
```

### Linux

```bash
make build-linux      # Produces release bundle
make package-linux    # Produces .tar.gz tarball
```

The output is in `build/linux/x64/release/bundle/`.

### Windows

```bash
make build-windows      # Produces release bundle
make package-windows    # Produces .zip archive
```

The output is in `build\windows\x64\runner\Release\`.

---

## macOS Code Signing and Notarization

Release builds for macOS are signed with a Developer ID certificate and notarized with Apple. This is handled automatically by the CI/CD pipeline for tagged releases, but you can also do it locally:

```bash
make sign-macos       # Sign with local Developer ID cert
make notarize-macos   # Sign, create DMG, notarize, and staple
```

Notarization requires Apple API credentials stored in a `.env` file (see [CI/CD](ci-cd.md) for the required secrets).

---

## SITL Testing

SITL (Software-In-The-Loop) lets you test Helios against a simulated ArduPilot vehicle without hardware.

```bash
make sitl
```

You can also use the built-in **Simulate** tab in Helios, which downloads the appropriate ArduPilot SITL binary on first use and provides a GUI for vehicle type, airframe, start location, wind, and failure injection.

For a lightweight alternative without SITL, the telemetry simulator generates synthetic MAVLink data:

```bash
make run-sim          # Basic telemetry simulator
make run-sim-full     # Telemetry + RTSP video stream
```

---

## Running Tests

```bash
make check            # Analyzer + all tests (recommended)
make test             # Tests only
make analyze          # Static analysis only
```

Tests live in `test/` and mirror the `lib/` directory structure. Use focused testing during development:

```bash
flutter test test/path/to/specific_test.dart
```

See [Contributing](contributing.md) for testing requirements when submitting changes.
