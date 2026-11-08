# Architecture — 360Sphere

## Original vs recreation

```
ORIGINAL (React Native)                    RECREATION (Flutter)
─────────────────────────                  ─────────────────────────
vision-camera preview  ──┐                 camera plugin preview ──┐
                          │                                          │
frame processors ────────┤→ Skia offscreen textures   takePicture ─→┤→ ui.Image frames
                          │   (SkiaCameraCanvas          (EXIF-aware │
gyro (expo-sensors) ─────┘    worklets)                   decode)   │
                          │                                          │
                          ▼                                          ▼
                equirectangular canvas               quaternion sensor fusion
                          │                          (gyro ∫ + accel/mag PID)
                          ▼                                          ▼
                    "Stitching" pass                     Canvas.drawVertices
                                                          textured mesh warp
                                                          (per-vertex feather)
                                                                     │
                                                                     ▼
                                                         4096×2048 equirect JPEG
                                                                     │
                                              ┌──────────────────────┼─────────┐
                                              ▼                      ▼         ▼
                                        My360s gallery        PSV viewer   Street View
                                        (index.json + jpg)    (WebView)    Publish API
```

Both pipelines share the same conceptual core the original's bundle reveals
(`SkiaCameraCanvas`, gyro-guided capture, PSV WebView viewer); the recreation
expresses it with Flutter's own rendering engine (Impeller/Skia) via
`dart:ui`.

## The stitching engine

### Orientation (device → world quaternion)

`lib/capture/orientation/`

- **Gyro integration** — each sample advances `q ← q ⊗ exp(ω·dt/2)` in the
  device frame.
- **Gravity correction (complementary/Mahony-style)** — the low-passed
  accelerometer direction gives the world-up axis in device coordinates; a
  proportional term (`gain ≈ 0.5 s⁻¹`) rotates the estimate so predicted
  gravity matches measured gravity, bounding pitch/roll drift.
- **Magnetic yaw correction** — optional (`compassAssist` setting): yaw error
  against the first-seen horizontal field direction, gain ≈ 0.4 s⁻¹. Only
  *relative* consistency matters for stitching, so no absolute calibration is
  needed.
- Sign conventions: ENU world (X east, Y north, Z up); device axes per
  Android sensor spec; back camera looks along device −Z; upright-portrait
  pose is `R_x(+90°)`.

### Projection

`lib/capture/stitching/equirect_projection.dart`

Equirect mapping: `λ = atan2(d.x, d.y)`, `φ = asin(d.z)`,
`x = (λ+π)/2π·W`, `y = (π/2−φ)/π·H` on a 2:1 canvas (4096×2048 default).

Each frame is a pinhole camera (`fovH` from settings, ~62° default). For a
mesh grid over the frame's spherical footprint, every vertex:

1. converts its equirect (λ, φ) to a world direction,
2. rotates it into the device frame with `q⁻¹`,
3. projects it through the pinhole to frame texture coordinates (u, v),
4. keeps per-vertex **alpha** that feathers from 1 inside the frustum to 0
   across a ~6° border ring.

Triangles whose corners are all invisible are dropped. Vertices beyond the
frustum clamp their UV (TileMode.clamp protects sampling) with alpha 0.

### Compositing

`lib/capture/stitching/equirect_stitcher.dart`

`Canvas.drawVertices(VertexMode.triangles, …)` paints the mesh with an
`ImageShader` of the camera frame — per-vertex colors modulate the shader for
the feather — over an accumulating offscreen image. **Seam handling**: mesh
positions are computed in *unwrapped* longitude, so a frame spanning the
±180° seam simply extends past the canvas edge; the stitcher draws the same
mesh again translated by ±W so the wrapped half lands on the opposite edge.

Coverage is tracked in 36×18 lon/lat bins (panorama mode: middle band only),
driving the HUD ring and the amber "next gap" arrow.

## Capture flow

`lib/capture/capture_session_controller.dart`

1. `start()` — camera preview + sensor subscriptions; tracker reset.
2. Auto sweep (`startAutoCapture`, ~0.8 s cadence) or manual shutter; each
   frame: orientation snapshot → `takePicture` → EXIF-aware decode (own
   mini EXIF orientation parser, aspect-heuristic fallback + manual override
   setting) → mesh warp into the accumulator.
3. `finish()` — optional watermark stamp → JPEG (quality 90) → repository
   (image + 512px thumbnail + `index.json`).

Differences from the original, by design (documented honestly):
still shots instead of a continuous frame stream; complementary filter
instead of a full commercial IMU fusion; no exposure-compensated blending.

## Viewer

`assets/viewer/viewer.html` (clean-room page) + vendored open-source runtime
(three.js, Photo Sphere Viewer 4, autorotate & gyroscope plugins — same
combination the original bundles). The Dart bridge loads the page from
Flutter assets, streams the JPEG as base64 chunks through
`window.appendChunk`, and reports state over a `PsvBridge` JS channel.

## Google Maps publishing

`lib/maps/` — three-call Street View Publish API v1 flow
(`photo:startUpload` → `PUT` bytes → `POST /v1/photo` with pose), authorized
by Google Sign-In with the `streetviewpublish` scope. See
[GOOGLE-MAPS-UPLOAD.md](GOOGLE-MAPS-UPLOAD.md) for OAuth setup.

## Testing

34 unit tests cover the entire math core — quaternion algebra and camera-aim
extraction, gyro/accel/mag fusion convergence, equirect round-trips, pinhole
projection, mesh building (aim-centering, seam crossing, uv clamping,
triangle expansion), coverage binning, and the EXIF orientation parser
(little/big endian). Run: `flutter test`.
