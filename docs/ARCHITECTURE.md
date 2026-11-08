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

Each frame is a pinhole camera (`fovH` from settings, ~62° default) — or,
in the fisheye mode, an **equidistant fisheye** (`ProjectionModel.fisheye`:
image radius r = θ / (diagonal FOV/2), where θ is the angle from the
optical axis; the configured FOV is the lens's full-circle diagonal). For a
mesh grid over the frame's spherical footprint, every vertex:

1. converts its equirect (λ, φ) to a world direction,
2. rotates it into the device frame with `q⁻¹`,
3. projects it through the pinhole (or fisheye) model to frame texture
   coordinates (u, v),
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
driving the HUD ring.

### Dot-target guidance (ported from the original capture worklet)

`lib/capture/dots/` — the original app's `useCaptureWorklet`, recovered from
the Hermes bundle, drives capture through a dot layout: 33 dots for a
photosphere (13 equator / 9 top @ ±45° / 9 bottom / ceiling / floor; 30 when
the camera FOV > 82°), one row/column per panorama mode, 3 × 120° + poles for
the fisheye mode. The `DotCaptureDirector` ports the worklet's semantics:

- target selection: sticky previous target, else nearest by
  `(0.2·|Δpitch|)² + |Δyaw|²` — pitch moves are cheap, so the guidance
  naturally row-jumps; polar dots only after all normal dots; the floor dot
  only when enabled;
- hold-to-capture: aim within 3° (pitch, yaw and roll), angular velocity
  under 5°/s, held 400 ms → the frame fires automatically
  (`NOT_CAPTURED → HOLDING → CAPTURING → CAPTURED`);
- when every dot is captured the session stitches itself.

## Capture flow

`lib/capture/capture_session_controller.dart`

1. `start()` — camera preview + sensor subscriptions; tracker reset; dot
   layout + director built for the selected mode.
2. **Hold-to-capture** (the original's mechanic): the director watches the
   gyro-derived aim; holding 400 ms on a target dot fires the shutter
   automatically. Manual shutter (and a legacy auto-timer API) remain as
   fallbacks. Each frame: orientation snapshot → `takePicture` → EXIF-aware
   decode (own mini EXIF orientation parser, aspect-heuristic fallback +
   manual override setting) → mesh warp into the accumulator; the dot is
   marked captured on success.
3. When every dot is captured — or the user taps ✓ — `finish()`: optional
   author watermark → JPEG (quality 90) → repository (image + 512px
   thumbnail + `index.json`).

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

53 unit tests cover the entire math core — quaternion algebra and camera-aim
extraction, gyro/accel/mag fusion convergence, equirect round-trips, pinhole
and fisheye projection, mesh building (aim-centering, seam crossing, uv
clamping, triangle expansion), coverage binning, dot layouts and the
hold-to-capture director, and the EXIF orientation parser
(little/big endian). Run: `flutter test`.
