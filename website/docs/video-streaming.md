# Video Streaming

Helios supports live RTSP video streaming with a telemetry HUD overlay, recording to disk, and full-screen display. Video playback is powered by `media_kit` with LGPL-compliant dynamic linking.

**Protocol**: Independent of MAVLink/MSP (any RTSP source)
**Platform**: Desktop only (macOS, Linux, Windows)

---

## RTSP Stream Setup

### URL format

Enter the RTSP URL for your camera in the Video View or in Setup > Video. The standard format is:

```
rtsp://<host>:<port>/<path>
```

### Common camera configurations

| Camera / Source | Typical URL |
|---|---|
| Generic IP camera | `rtsp://192.168.0.10:554/stream1` |
| Companion computer (e.g. RPi) | `rtsp://192.168.0.10:8554/main` |
| SITL / local test | `rtsp://127.0.0.1:8554/stream` |
| DJI-style WiFi camera | `rtsp://192.168.0.1:554/live` |

Replace the host, port, and path to match your camera's documentation. Some cameras require authentication in the URL:

```
rtsp://username:password@192.168.0.10:554/stream1
```

### Connection

1. Enter the RTSP URL in the text field on the Video View landing screen (or configure it in Setup > Video).
2. Tap **Connect** (or press Enter).
3. The video surface fills the screen when the stream connects.

If the stream fails, an error message is displayed below the URL field.

### Settings

| Setting | Description |
|---|---|
| Low-latency mode | Reduces the decode buffer for real-time video. Recommended for FPV use. |
| Auto-connect on launch | Automatically connects to the saved URL when the app starts. |

Both settings are configured in Setup > Video and persisted across sessions.

---

## Video HUD Overlay

When a vehicle is connected, a transparent telemetry HUD is rendered on top of the video stream. The HUD shows flight-critical data without switching views.

### HUD elements

| Position | Element | Data |
|---|---|---|
| Left tape | Speed | Indicated airspeed (IAS) in m/s |
| Right tape | Altitude | Altitude AGL (ALT) in metres |
| Top centre | Heading | Compass heading in degrees |
| Bottom centre | Mode + Arm | Current flight mode and arm state |
| Bottom left | Battery | Voltage and remaining percentage |
| Bottom right | GPS | Satellite count and ground speed |
| Centre right | Climb rate | Vertical speed with +/- indicator |

The speed and altitude tapes use the same style as the PFD for consistency.

### Toggling the HUD

Tap the **HUD** button in the top control bar to show or hide the overlay. The toggle state is not persisted -- the HUD is shown by default when a stream is active.

---

## Video Recording

Helios records RTSP streams to disk using `ffmpeg`. Recordings are saved as `.mp4` files in the app's documents directory under `helios_recordings/`.

### Requirements

- `ffmpeg` must be installed and accessible on PATH.

### How to record

1. Connect to an RTSP stream.
2. Tap the **Record** button in the top control bar.
3. The button changes to **Stop Rec** with a red indicator while recording.
4. Tap **Stop Rec** to end the recording.

### Recording files

| Property | Value |
|---|---|
| Format | MP4 (or MKV) |
| Location | `<app documents>/helios_recordings/` |
| Naming | Timestamped filename |

### Recordings panel

When the video stream is disconnected, a recordings panel appears at the bottom of the Video View listing all saved recordings. Each entry shows:

- Filename
- Date and time
- File size

Actions per recording:

| Action | Description |
|---|---|
| Play | Opens the recording in the video player |
| Delete | Removes the file from disk |

---

## Full-Screen Mode

The Video View fills the entire content area by default (no sidebar or navigation chrome). Tap anywhere on the video to toggle the top control bar visibility.

The control bar provides quick access to:

- Stream status indicator (green when connected)
- Current RTSP URL
- HUD toggle
- Play / Stop stream
- Record / Stop recording

---

## Platform Support

| Feature | macOS | Linux | Windows | iOS | Android |
|---|:---:|:---:|:---:|:---:|:---:|
| RTSP streaming | Yes | Yes | Yes | -- | -- |
| HUD overlay | Yes | Yes | Yes | -- | -- |
| Video recording | Yes | Yes | Yes | -- | -- |
| Recording playback | Yes | Yes | Yes | -- | -- |

Video streaming is desktop-only. The `media_kit` library provides cross-platform media playback via dynamic linking to system FFmpeg/libmpv libraries, maintaining LGPL compliance.

iOS and Android are not supported because `media_kit` desktop backends are required for RTSP stream handling. On mobile platforms, the Video tab displays a "Video not available" message.
