# Installation

Download and install Helios GCS on macOS, Linux, Windows, Android, or iOS. Prebuilt packages are available for every release.

---

## Download

Prebuilt packages are published with each [GitHub Release](https://github.com/jamesagarside/helios/releases). Download the latest version for your platform:

| Platform | Package | Format |
|---|---|---|
| macOS | `helios-gcs-macos.dmg` | Signed and notarized DMG installer |
| Linux | `helios-gcs-linux-x64.AppImage` | Portable AppImage (recommended) |
| Linux | `helios-gcs-linux-x64.tar.gz` | Portable tarball |
| Windows | `helios-gcs-windows-x64-setup.exe` | Installer |
| Windows | `helios-gcs-windows-x64.zip` | Portable zip archive |
| Android | `app-release.apk` | Sideload APK |
| iOS | `*.ipa` | Signed IPA (TestFlight or sideload) |

### macOS

1. Download `helios-gcs-macos.dmg` from the latest release.
2. Open the DMG and drag **Helios GCS** into your **Applications** folder.
3. Launch Helios from Applications. On first launch, macOS may prompt you to confirm because the app was downloaded from the internet -- click **Open**.

The macOS build is code-signed with a Developer ID certificate and notarized with Apple, so Gatekeeper will allow it to run without disabling security settings.

### Linux

**AppImage (recommended):** Download `helios-gcs-linux-x64.AppImage`, make it executable, and run:

```bash
chmod +x helios-gcs-linux-x64.AppImage
./helios-gcs-linux-x64.AppImage
```

**Tarball:** Download `helios-gcs-linux-x64.tar.gz` and extract:

```bash
mkdir -p ~/helios
tar xzf helios-gcs-linux-x64.tar.gz -C ~/helios
~/helios/helios_gcs
```

You may want to create a desktop entry or symlink the binary into your `PATH` for convenience.

### Windows

**Installer (recommended):** Download `helios-gcs-windows-x64-setup.exe` and run it. The installer creates a Start Menu shortcut and optional desktop icon.

**Portable:** Download `helios-gcs-windows-x64.zip`, extract to a folder of your choice (e.g. `C:\Helios`), and run `helios_gcs.exe`.

### Android

Helios is distributed as a direct APK download during the alpha period.

1. Download `app-release.apk` from the latest [GitHub Release](https://github.com/jamesagarside/helios/releases).
2. On your Android device, open the downloaded APK file.
3. If prompted, enable **Install from unknown sources** for your browser or file manager (Settings > Apps > Special access > Install unknown apps).
4. Tap **Install** and then **Open**.

**Note:** USB serial connections are not available on Android. Connect to your flight controller over UDP or TCP via a telemetry radio or Wi-Fi bridge.

### iOS

iOS builds are available as signed IPA files from each [GitHub Release](https://github.com/jamesagarside/helios/releases).

**Note:** USB serial connections are not available on iOS. Connect to your flight controller over UDP or TCP via a telemetry radio or Wi-Fi bridge.

---

## DuckDB Native Library

Helios uses DuckDB for flight recording. The native library must be available at runtime.

### macOS

The DuckDB dynamic library must be at `/usr/local/lib/libduckdb.dylib`. If it is missing, copy it from the vendored location:

```bash
sudo cp native/macos/libduckdb.dylib /usr/local/lib/libduckdb.dylib
```

### Linux

Place `libduckdb.so` in a directory on your `LD_LIBRARY_PATH`, or install it to `/usr/local/lib`:

```bash
sudo cp native/linux/libduckdb.so /usr/local/lib/
sudo ldconfig
```

### Windows

Place `duckdb.dll` in the same directory as the Helios executable, or add its location to your system `PATH`.

---

## Serial Port Support

Helios uses `flutter_libserialport` for USB serial connections to flight controllers.

**macOS**: The macOS sandbox is disabled in the app entitlements to allow direct serial port access. No additional configuration is needed.

**Linux**: Your user account must be in the `dialout` group to access serial ports without root:

```bash
sudo usermod -aG dialout $USER
```

Log out and back in for the group change to take effect.

**Windows**: Serial ports are accessible by default. Install the appropriate USB driver for your flight controller (most ArduPilot boards use a built-in USB CDC driver).

---

## SITL Simulator

If you want to test Helios without hardware, you can launch an ArduPilot SITL simulation directly from the **Simulate** tab inside Helios. SITL downloads the appropriate ArduPilot binary on first use -- no Docker or manual setup required.

See the [Simulate documentation](simulate.md) for details on vehicle type, airframe, start location, wind, and failure injection options.

---

## Troubleshooting

### DuckDB dylib not found

**Symptom**: App crashes on launch or flight recording fails with a library-not-found error.

**Fix (macOS)**:

```bash
sudo cp native/macos/libduckdb.dylib /usr/local/lib/libduckdb.dylib
```

**Fix (Linux)**:

```bash
sudo cp native/linux/libduckdb.so /usr/local/lib/
sudo ldconfig
```

Verify the library is loadable:

```bash
# macOS
otool -L /usr/local/lib/libduckdb.dylib

# Linux
ldconfig -p | grep duckdb
```

### Serial port permission denied (Linux)

**Symptom**: Connection fails with "permission denied" when selecting a USB serial port.

**Fix**: Add your user to the `dialout` group and log out/in:

```bash
sudo usermod -aG dialout $USER
```

### Serial port not detected (macOS)

**Symptom**: No serial ports appear in the connection dropdown.

**Fix**: Ensure your flight controller's USB cable is connected and the board is powered. Some boards require a specific USB driver -- check your flight controller's documentation. Silicon Labs CP210x and FTDI drivers are the most common.

### App won't open on macOS ("damaged" or "unidentified developer")

**Symptom**: macOS refuses to open Helios with a security warning.

**Fix**: The release DMG is signed and notarized. If you still see this warning, try:

```bash
xattr -cr /Applications/helios_gcs.app
```

Then open the app again. This clears the quarantine attribute that macOS sets on downloaded files.

---

## Building from Source

If you want to build Helios from source, contribute to the project, or modify the code, see the [Building from Source](building-from-source.md) guide in the Development section.
