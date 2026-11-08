# Revision — original 360 Photo Cam vs 360Sphere

A feature-by-feature pass over the original app's decompiled bundle
(`index.android.bundle`, Hermes HBC v96; see [REA-ANALYSIS.md](REA-ANALYSIS.md))
against this recreation, produced by re-reading the worklet sources and the
string table. Each row records what the original does, where the evidence
lives, what the recreation had, and the decision taken in this revision.

## Ported in this revision

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
| Hosted share links (`share.360photo.cam/viewer/`), short links, Facebook posting | Requires the original's backend (`360app.dospace.tech`) — out of the core-pipeline scope; the API surface is documented in REA-ANALYSIS.md for a future backend. |
| Community showcase, comments, content guidelines | Backend + moderation features. |
| Auth (email code / Apple / Google sign-in for the app account), unlock credits, watermark lock, subscriptions (RevenueCat `10_credits_monthly`, Lifetime) | Monetization and account system; the recreation is offline-first and free of the credit economy. |
| Push notifications (OneSignal), Branch deep links, analytics events | Growth/engagement infrastructure tied to the backend. |
| "Not a 360° Photo" import validation | The recreation has no import flow to validate. |
| `FILTER_ALPHA = 0.5` sensor low-pass | Equivalent behaviour already exists in the complementary filter (gravity low-pass + proportional correction). |

## Test coverage added

- `test/capture/capture_dots_test.dart` — layout counts (33/30, rows,
  spacing, floor exclusion, panorama presets), `angleDiffW` parity,
  target-selection semantics (nearest, sticky, row-jumping per pitchWeight,
  polar-last, floor skip), hold machine (400 ms completion, break-on-move,
  velocity and roll gates), arrow guidance directions.
- `test/capture/fisheye_projection_test.dart` — equidistant mapping, rim
  cases, rejection outside the lens circle, mesh-builder smoke test.

53 unit tests total, `flutter analyze` clean.
