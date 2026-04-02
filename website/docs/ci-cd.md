# CI/CD

Helios uses GitHub Actions for continuous integration and automated release builds. All pipelines are defined in `.github/workflows/`.

---

## Pipelines

### CI (`ci.yml`)

Runs on every push to `main` and `develop`, and on pull requests targeting `main`.

**Steps:**

1. Check out the repository.
2. Set up Flutter (stable channel).
3. Install dependencies (`flutter pub get`).
4. Run static analysis (`dart analyze --fatal-warnings`).
5. Run all tests (`flutter test`).

A passing CI check is required before merging any pull request.

### Release Desktop (`release-desktop.yml`)

Triggered when a version tag is pushed (e.g. `v0.3.0`). Builds release packages for all three desktop platforms in parallel, then creates a GitHub Release with the artifacts.

**macOS build:**

1. Install build dependencies (automake, libtool).
2. Import the signing certificate from repository secrets.
3. Build the macOS release (`flutter build macos --release`).
4. Sign all nested frameworks and the app bundle (inside-out signing).
5. Create and sign a DMG installer.
6. Notarize the DMG with Apple and staple the ticket.
7. Upload `helios-gcs-macos.dmg` as a build artifact.

**Linux build:**

1. Install system dependencies (clang, cmake, ninja, GTK3, libserialport, libmpv).
2. Build the Linux release.
3. Create a tarball (`helios-gcs-linux-x64.tar.gz`).

**Windows build:**

1. Build the Windows release.
2. Create a zip archive (`helios-gcs-windows-x64.zip`).

**Release creation:**

After all three platform builds succeed, a GitHub Release is created with auto-generated release notes and all three artifacts attached.

### Release Mobile (`release-mobile.yml`)

Builds mobile packages (Android APK/AAB, iOS IPA) for tagged releases.

### Deploy Website (`deploy-website.yml`)

Deploys the documentation website on pushes to `main`.

---

## Secrets

The following GitHub repository secrets are required for the release pipeline:

| Secret | Purpose |
|---|---|
| `MACOS_CERTIFICATE` | Base64-encoded Developer ID Application certificate (.p12) |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the .p12 certificate |
| `KEYCHAIN_PASSWORD` | Password for the temporary CI keychain |
| `APPLE_API_KEY_CONTENT` | Base64-encoded App Store Connect API key (.p8) |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect API issuer ID |

---

## Creating a Release

To publish a new release:

1. Ensure all changes are merged to `main` and CI is passing.
2. Tag the release:

```bash
make release V=0.3.0
```

This creates an annotated git tag `v0.3.0` and pushes it to origin. GitHub Actions automatically builds all platform packages and creates a GitHub Release with the artifacts.

3. Verify the release on the [GitHub Releases page](https://github.com/jamesagarside/helios/releases).

---

## Local Equivalents

Every CI step can be run locally with Make:

| CI Step | Local Command |
|---|---|
| Static analysis | `make analyze` |
| Tests | `make test` |
| Full CI check | `make check` |
| macOS release build | `make build-macos` |
| macOS DMG | `make package-macos` |
| macOS sign + notarize | `make notarize-macos` |
| Linux release build | `make build-linux` |
| Linux tarball | `make package-linux` |
| Windows release build | `make build-windows` |
| Windows zip | `make package-windows` |
