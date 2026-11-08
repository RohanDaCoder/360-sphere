# Revision — original 360 Photo Cam vs 360Sphere

A feature-by-feature pass over the original app's decompiled bundle
(`index.android.bundle`, Hermes HBC v96; see [REA-ANALYSIS.md](REA-ANALYSIS.md))
against this recreation. Wave 1 re-read the worklet sources and string
table; Wave 2 went deeper — decompiling the native `OrientationAngle`
module with apkscope, tracing the cloud rendering pipeline, and recovering
the Street View alert mapping, the PhotoNameScreen flow and the import
flow from the bundle. Each row records what the original does, where the
evidence lives, what the recreation had, and the decision taken.

## Wave 2 — deep revision pass (this change)

### 1. Native orientation pipeline (`OrientationAngle` module)

**Original** — the capture UI does not read raw sensors. A native module
(`com.reactnativeorientationangle.OrientationAngleModule`, decompiled with
apkscope) feeds it filtered camera-pose angles:

| Stage | Original behaviour |
| --- | --- |
| Sensor | `TYPE_GAME_ROTATION_VECTOR` preferred, `TYPE_ROTATION_VECTOR` fallback (relative yaw — no magnetic re-referencing jumps) |
| Rate | throttled to 30 ms (`SENSOR_INTERVAL`) on a dedicated handler thread |
| Euler | `pitch = atan2(2(wx+yz), 1−2(x²+y²)) − 90°` (upright phone = 0°), `roll = asin(2(wy−xz))`, `yaw = −atan2(2(xy+wz), 1−2(y²+z²))` |
| Glitch guard | raw yaw delta clamped to **±25°** per reading (`MAX_RAW_YAW_DELTA`) |
| Smoothing | low-pass **α = 0.8** on all three angles (yaw diff taken on the wrapped circle) |
| Output | `pitch` / `roll` / `yaw` events consumed by the `useCaptureWorklet` dot director |

**Recreation now** — `lib/capture/orientation/original_orientation_filter.dart`
is a faithful Dart port of exactly that math (same clamping, same α,
same ±360-only `normalizeAngle` semantics), applied to the quaternion
tracker's output and fed to the dot director, replacing the ad-hoc
cameraAim-derived angles.

### 2. GPano XMP metadata (the "real 360° photo" stamp)

**Original** — its photos carry the `GPano` XMP packet (added server-side
by the cloud stitcher); Google Street View rejects uploads without it and
the app maps that rejection to its *"Not a 360° Photo"* alert.

**Recreation now** — `lib/capture/stitching/xmp_pano.dart` writes the
packet itself: an `APP1` segment inserted directly after SOI with
`ProjectionType=equirectangular`, `UsePanoramaViewer=True`, full-pano /
cropped-area dimensions and `CaptureSoftware`. Applied at stitch time, on
imported photos that lack it, and checked before every Street View
upload (`preflightCheck`).

### 3. Four-step processing screen

**Original** — the processing card shows the photo thumbnail plus
*"Stitching... Step X/4"* and finally *"Finishing... Step 4/4"*, with a
46-frame `rendering/` animation driven by a 1300 ms polling loop while
the cloud stitches (`useRenderingHistoriesUpdater`, `getRenderingCntUsingStore`).

**Recreation now** — the local finisher reports the same four steps
(composite → encode → thumbnail → store) and the overlay renders the
thumbnail, the step counter and a progress bar. Local stitching means no
polling loop and no animation frames are needed.

### 4. Photo name + description (PhotoNameScreen)

**Original** — a PhotoNameScreen collects *"Photo name"* (maxLength 200)
and *"Photo description"* with a Save button; empty names are rejected
with *"Photo name can't be empty"*.

**Recreation now** — the detail screen's edit dialog collects both fields
(200-char name, validation message included); `Photosphere.description`
persists through the repository and shows on the detail page.

### 5. Import flow

**Original** — an Import button (`Import_Button_Pressed`) picks an
existing photo; non-360 photos are rejected (*"Not a 360° Photo"*,
*"Failed to import file"*, temp dir `/temp_import_`, default name
*"Imported Photo"*).

**Recreation now** — My 360s gains an Import button (`image_picker`);
`validateForImport` accepts photos carrying equirectangular GPano
metadata *or* a 2:1 aspect ratio (±2%), with the original's rejection
messages. Imported photos without metadata get the GPano stamp so they
publish to Street View like captured ones.

### 6. Street View error dialogs

**Original** — upload failures are classified into eight alert dialogs
(recovered verbatim from the bundle):

| Dialog title | Trigger (error text includes…) |
| --- | --- |
| `Upload Failed` | anything unrecognised / `INVALID_ARGUMENT` (generic) |
| `Location Required` | `location`, `latitude`, `longitude` |
| `Photo Too Large` | `too large`, `size` |
| `Already Uploaded` | `already exists`, `ALREADY_EXISTS` |
| `Connection Error` | `network`, `timeout`, `ETIMEDOUT` |
| `Not a 360° Photo` | missing 360 metadata (`INVALID_ARGUMENT` after upload) |
| `Google Account Token Expired` | auth token expired |
| `Permission Required` | Street View scope not granted |

**Recreation now** — `lib/maps/streetview_errors.dart` mirrors the
classification (plus a client-side `preflightCheck` that raises *"Not a
360° Photo"* before wasting an upload) and the publish sheet renders the
title + message pair.

### 7. Viewer configuration parity

**Original viewer.html** — `navbar: false`, `defaultZoomLvl: 0`,
`AutorotatePlugin { autostartOnIdle: false, autorotateSpeed: '3rpm' }`,
`GyroscopePlugin { touchmove: true, absolutePosition: false }`; the Play
button is what starts rotation.

**Recreation now** — the vendored page matches exactly. This also fixes a
real bug: we passed `touch: false` to the gyroscope plugin, an option
that does not exist in PSV 4.x (the correct option is `touchmove`), so
the setting was silently ignored.

### 8. First-run capture instructions

**Original** — two instruction overlays on the camera:
*"Plant your feet and rotate in one spot."* and *"Stand 3-4 feet away
from nearby objects or surfaces."*

**Recreation now** — a dismissible first-run overlay with the same two
hints (persisted in `SharedPreferences`), in addition to the existing
help sheet.

## Wave 1 — first revision pass

### 1. Dot-target guided photosphere capture

**Original** — the capture screen places a set of target dots around the user
and auto-captures when the phone is held on one. Evidence: the
`useCaptureWorklet` source (recovered verbatim in the bundle's string table)
plus the layout construction in the decompiled module:

- rows `['ceiling', 'top', 'middle', 'bottom', 'floor']`;
- photosphere layout: `middle` 13 dots @ pitch 0°, `top` 9 @ +45°,
  `bottom` 9 @ −45°, `ceiling` 1 @ +90°, `floor` 1 @ −90° — **33 dots**,
  reduced to **30** (12/8/8/1/1) when the camera FOV is wider than **82°**;
- status machine `NOT_CAPTURED → HOLDING → CAPTURING → CAPTURED`
  (`CAPTURE_STATUS` enum in the constants block);
- hold detection: aim within `holdDeltaAngle = 3°` on pitch and yaw (roll
  must also be within 3°), angular velocity below
  `MAX_ANGULAR_VELOCITY = 5°/s`, held for `CAPTURE_HOLD_DURATION = 400 ms`;
- target selection: sticky previous target, else nearest by
  `len = (|Δpitch|·pitchWeight)² + |Δyaw|²` with `pitchWeight = 0.2`;
  polar dots only after all normal dots; the floor dot only when
  `inFloorCapture` is on;
- guidance: an arrow at a fixed radius that hides within
  `deltaArrowAngle = 6°` of the target and points straight up/down for
  ceiling/floor; a **rectangle outline** (177 × 255, ratio-scaled) for normal
  targets and a **circle outline** (radius 87) for polar targets;
  dot visibility radius `deltaView2 = 2000` (deg²) with the original's
  `TransformedGreenTarget` 3D-style transforms (opacity 1 target / 0.4 rest).

**Recreation now** — `lib/capture/dots/capture_dots.dart` (layouts),
`lib/capture/dots/dot_capture_director.dart` (a pure-Dart semantics port of
the worklet: same constants, same selection metric, same hold machine), and a
new HUD (`lib/capture/widgets/capture_hud.dart`) that draws the green target
dots, hold progress ring, direction arrow, rect/circle outlines, captured
counter and the coverage ring. The session auto-finishes when every dot is
captured (the original's `PROCESS_STATUS` → `PROCESSING` transition).

### 2. The missing panorama modes

**Original** — mode identifiers `panorama-wide-angle`, `panorama-vertical`,
`panorama-horizontal`, `panorama-fisheye` (string table / `PHOTOSPHERE_TYPE`).

**Recreation now** — `CaptureMode` extends to all five. Each mode gets a dot
layout: horizontal 8, wide-angle 6, vertical 9 (pitch −60°…+60° column),
fisheye 3 × 120° + ceiling + floor.

### 3. Fisheye (equidistant) lens projection

**Original** — the fisheye panorama mode captures through a clip-on fisheye
lens (180° class).

**Recreation now** — `FrameCamera` gains a `ProjectionModel.fisheye`
equidistant mapping (`r = θ / (FOV/2)`), used by the mesh warp when the
fisheye mode is active; the settings FOV slider now reaches 180°.

### 4. Author watermark

**Original** — `"Created in 360 Photo Cam by "` + author (string table; the
watermark economy around it — guest watermarks, unlock credits — is backend
monetization and stays out of scope).

**Recreation now** — `Settings.authorName` and
`watermarkLabel` = "Created in 360Sphere by {author}", rendered by the
stitcher on finalize.

### 5. Viewer toolbar

**Original** — viewer analytics strings recover the button set: Close,
Delete, **Download**, **Share**, **Google Maps**, Post, Unlock, **Gyroscope**,
**Play** (autorotate), Menu (`*_Button_Tapped_On_*_Viewer_Screen` strings).

**Recreation now** — the viewer app bar gains Play/pause (autorotate via a
new `setAutorotate` bridge into the vendored PSV AutorotatePlugin), a
gyroscope toggle with active state, Share, Save-to-gallery and Delete
(callbacks wired from the gallery detail screen). Post/Unlock are backend
features (see below).

### 6. Floor-capture toggle

**Original** — `inFloorCapture` shared value on the capture screen.

**Recreation now** — `Settings.includeFloorCapture` (also drives whether the
photosphere/fisheye layouts include the floor dot).

## Reviewed and skipped (with reasons)

| Original feature | Why not ported |
| --- | --- |
| Cloud stitching / rendering pipeline (frame upload → server stitch → `processingState` polling, transfer statuses, 46-frame rendering animation) | Requires the original's backend; the recreation stitches locally on-device instead, reporting the same 4-step progress UX. The cloud API surface is documented in REA-ANALYSIS.md. |
| Spatial comment pins in the viewer (marker layer, long-press → yaw/pitch, fly-to, reply badges) | Community feature — depends on the comments backend (`/api/v2/comments/`). The long-press → spherical coordinate math is documented in REA-ANALYSIS.md should a local annotation layer ever be wanted. |
| Hosted share links (`share.360photo.cam/viewer/`), short links, Facebook posting | Requires the original's backend (`360app.dospace.tech`) — out of the core-pipeline scope; the API surface is documented in REA-ANALYSIS.md for a future backend. |
| Community showcase, content guidelines | Backend + moderation features. |
| Auth (email code / Apple / Google sign-in for the app account), unlock credits, watermark lock, subscriptions (RevenueCat `10_credits_monthly`, Lifetime) | Monetization and account system; the recreation is offline-first and free of the credit economy. |
| Push notifications (OneSignal), Branch deep links, analytics events | Growth/engagement infrastructure tied to the backend. |
| "Open on Google Maps" link for published photos | Needs the published photo's pose to be stored and a URL launcher dependency; the Street View photo id is kept and shown instead. |
| "Slow Connection Detected" banners, "Please allow access to the Camera from settings" dialog | Tied to the cloud flow / a permission-handler dependency; the camera plugin already surfaces permission errors with a Retry action. |

## Test coverage added

### Wave 2

- `test/capture/original_orientation_filter_test.dart` — euler conventions
  (flat −90, upright 0, ±45 tilts, sideways roll ±90), yaw jump clamping
  (±25° then α=0.8 → ±20°), step convergence, non-default alpha, reset
  semantics, quiet-stream stability, `angleDeltaDeg` wraparound.
- `test/capture/xmp_pano_test.dart` — packet contents (projection, viewer,
  pano/crop dimensions, heading, XML-escaped title), APP1 insertion right
  after SOI, byte preservation, replace-not-duplicate, non-JPEG rejection,
  detection helpers.
- `test/gallery/import_service_test.dart` — import acceptance (GPano path,
  2:1 fallback, tolerance), rejections (non-2:1, non-JPEG, wrong
  projection), `jpegSize` SOF parsing.
- `test/maps/streetview_errors_test.dart` — all eight dialog
  classifications, network errors outside the service exception,
  `preflightCheck` accept/reject.

### Wave 1

- `test/capture/capture_dots_test.dart` — layout counts (33/30, rows,
  spacing, floor exclusion, panorama presets), `angleDiffW` parity,
  target-selection semantics (nearest, sticky, row-jumping per pitchWeight,
  polar-last, floor skip), hold machine (400 ms completion, break-on-move,
  velocity and roll gates), arrow guidance directions.
- `test/capture/fisheye_projection_test.dart` — equidistant mapping, rim
  cases, rejection outside the lens circle, mesh-builder smoke test.

94 unit tests total, `flutter analyze` clean.
