# Render the Airframe Model with a custom `Canvas.drawVertices` renderer, not a 3D engine

**Status:** accepted

The Airframe Model (the real-time, frame-aware 3D representation of the vehicle) is rendered by a hand-built renderer using stable `dart:ui` `Canvas.drawVertices` plus `vector_math` `Matrix4`/`Quaternion`, rather than adopting a 3D engine package. We evaluated `flutter_scene`, `three_js`, `flutter_cube`, and `model_viewer_plus` (2026). The custom approach is the only option that simultaneously runs on all six targets **including Flutter web** (CanvasKit/Skwasm render `drawVertices` correctly; the old "broken on web" reports were against the removed HTML renderer), supports **procedural, frame-aware geometry** built at runtime from `FRAME_CLASS`/`FRAME_TYPE`, and stays on the **stable SDK** (`flutter_scene` needs the master channel; `model_viewer_plus` has no desktop support).

## Considered Options

- **`flutter_scene`** — Impeller-native, from the Impeller author; but requires the master channel and is explicitly "early preview." Re-evaluate when it reaches stable.
- **`three_js` (Knightro63)** — full cross-platform via its own ANGLE/WebGL2 context; the documented escalation path if poly count grows and we need a real depth buffer and GPU lighting. Overkill for a low-poly attitude indicator.
- **`flutter_cube`** — same `drawVertices` core and a procedural `Mesh` constructor, but unmaintained since ~2019. Useful as reference code to fork, not a dependency.
- **`model_viewer_plus`** — disqualified: no desktop support, GLB files only (no procedural meshes), no clean per-frame rotation control.

## Consequences

- No hardware depth buffer — we z-sort faces with the painter's algorithm, which is sufficient for a convex-ish airframe silhouette.
- CPU-bound projection, fine for low-poly at the render rate; not suitable if the model ever becomes high-poly (that would be the trigger to revisit `three_js`).
- The render loop extends the existing **PFD Ticker-interpolation** pattern (recorded in the `CLAUDE.md` Key Technical Decisions table — "60fps smooth rendering between telemetry samples"): a Ticker repaints at display refresh and `slerp`s toward the latest quaternion sample, decoupling render rate from telemetry rate.
