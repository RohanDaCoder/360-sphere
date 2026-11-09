# REA Analysis — 360 Photo Cam (com.dospace.photo360)

> Reverse-engineering findings that informed this recreation. Produced with a
> local, evidence-first toolchain; every claim below cites where it came from.

## Subject

| Property | Value |
| --- | --- |
| App | **360 Photo Cam** (`360+Photo+Cam_4.1.0_APKPure.apk`) |
| Package | `com.dospace.photo360` |
| Version | 4.1.0 (3006566) |
| min / target SDK | 24 / 36 |
| APK SHA-256 | `bc945ac29fd5b645f0c1d7f9770b29982b01f01e7a553bb46cb79f69f9f98c17` |
| Size / contents | 78 MB, 1,214 files, 7 DEX, 25,822 classes, 361,927 methods |
| Support | 360photo@dospace.tech |

## Method

1. **REA** (`rea-agents` 6.8.0 CLI + MCP) — `rea info`, `rea manifest`, class listing, URL/string recon over the DEX.
2. **apkscope 0.9.0** — typed Java view of the DEX: `info`, `classes`, `decompile`, `search urls`.
3. **hermes-dec** — decompilation of the 5.4 MB `assets/index.android.bundle` (Hermes bytecode, HBC v96) into 937,513 lines of readable pseudocode plus the full string table (20,470 unique strings at first pass; 33,270 literals recovered on the Wave-3 re-run).
4. **jadx 1.5.1** (Wave 3 re-run, fresh sandbox) — DEX → Java for the app-owned classes (`--single-class … --show-bad-code` recovered the full `quaternionToEuler` body) and resource decoding for `AndroidManifest.xml`.

## Findings

### Technology stack

| Layer | Original app |
| --- | --- |
| Framework | React Native (Expo CNG), **Hermes** bytecode, New Architecture (Fabric) |
| Camera | `react-native-vision-camera` (mrousavy) + `@shopify/react-native-skia` (`SkiaCameraCanvas` worklets found in the bundle) |
| Navigation | React Navigation (native stack + bottom tabs) |
| Viewer | WebView + **Photo Sphere Viewer 4** (three.js) with autorotate + gyroscope plugins, bundled in `assets/viewer/` |
| Push | OneSignal (FCM + HMS) |
| Auth | Firebase Auth (Google / Apple / email code) |
| Monetization | RevenueCat (`Premium` entitlement, `10_credits_monthly`, lifetime option) + Play Billing + Amazon IAP |
| Deep links | Branch (`assets/branch.json`) |
| Fonts | AzoSans, Montserrat, Inter (bundled) |

Evidence: `MainApplication` extends `DefaultReactNativeHost` with `isHermesEnabled = true` (decompiled Java); `SkiaCameraCanvasTsx1` worklet source embedded in the Hermes bundle; viewer plugin files in `assets/viewer/js/`.

### Screens (from the bundle's string table)

`RootNavigator` → bottom tabs / stack: **Camera, Capture, Community, My360s, Premium, Settings, Stitching, Subscription** — plus **PhotoNameScreen** (photo name + description editor) and **PhotoActionsModal**.

### Capture modes

`panorama-wide-angle`, `panorama-vertical`, `panorama-horizontal`, `panorama-fisheye`, plus the flagship **photosphere** (gyroscope-guided) — icon names recovered from the bundle strings.

### Deep findings (Wave 2)

#### The native `OrientationAngle` module

`com.reactnativeorientationangle.OrientationAngleModule` (decompiled with
apkscope, re-verified with jadx on a fresh sandbox — the only app-owned
native module besides `MainActivity`, `InAppReviewModule` and
`MainApplication`):

- listens to `TYPE_GAME_ROTATION_VECTOR` (fallback `TYPE_ROTATION_VECTOR`)
  on a dedicated `HandlerThread`; the native default interval is 100 ms,
  but the JS constants module immediately calls
  `setUpdateInterval(SENSOR_INTERVAL)` with **30 ms** (`SENSOR_INTERVAL_LOW`
  = 50 ms exists for a low-power mode);
- converts the quaternion to camera-pose euler angles
  (`pitch−90°` with a range fix — atan2 values in (−180, −90) get +360°
  so pitch stays in (−180, 180]; `roll = asin(2(wy−xz))`;
  `yaw = −atan2(2(xy+wz), 1−2(y²+z²))`);
- `normalizeAngle` **wraps into [−180, 180]** (`d > 180 → d−360`,
  `d < −180 → d+360`) — an earlier note here claimed it only guarded ±360;
  the fresh decompile corrected that (it matters for yaw deltas across
  the ±180° seam);
- clamps raw yaw deltas to ±25° per reading, low-pass filters pitch/roll/yaw
  with α = 0.8 (yaw differences on the wrapped circle);
- emits `pitch`/`roll`/`yaw` events consumed by the capture worklet.

Ported verbatim in `lib/capture/orientation/original_orientation_filter.dart`
(see [REVISION.md](REVISION.md) §Wave 2 and the two fidelity fixes in
§Wave 3).

#### Stitching is server-side

The photosphere pipeline uploads captured frames to the backend
(`https://360app.dospace.tech`, AWS S3 presigned URLs) and **the cloud
stitches**. The app polls photo state:

```text
GET /photo/{id}?view=INCLUDE_DOWNLOAD_URL   (Bearer token)
  processingState: PENDING | PROCESSING | PROCESSED | FAILED
  transferStatus:  NEVER_TRANSFERRED | PROCESSING | COMPLETED | REJECTED
                  | EXPIRED | CANCELLED | RECEIVED_VIA_TRANSFER
  mapsPublishStatus: PUBLISHED | REJECTED | REJECTED_UNKNOWN | …
```

While rendering, the processing card shows the thumbnail plus
`"Stitching... Step X/4"` → `"Finishing... Step 4/4"` with a 46-frame
animation (`assets/rendering/frame_0..45.jpg`) cycled by a 1300 ms
`setInterval` (`useRenderingHistoriesUpdater` incrementing a
`renderingCnt` in the app's persistent store). The GPano XMP metadata on
finished photos is added by this server pipeline.

#### Street View publish service (recovered from the bundle)

The JS service is a three-step client:
`photo:startUpload` (Bearer token, empty body) → PUT the JPEG to the
presigned `uploadUrl` → `POST /v1/photo` with
`{uploadReference, pose: {latLngPair: {latitude, longitude}, heading},
captureTime: {seconds}}`. The response is mined for `photoId.id` **and**
`shareLink` (a Google Maps URL the viewer's Google Maps button opens).
The pose comes from the photo's stored `geo_location`
{latitude, longitude, heading} captured by the geolocation hook at capture
time — not re-fixed at upload time. Failures map to the eight alert
dialogs below.

#### Street View alert mapping (recovered verbatim)

`Upload Failed` · `Location Required` · `Photo Too Large` ·
`Already Uploaded` · `Connection Error` · `Not a 360° Photo` ·
`Google Account Token Expired` · `Permission Required` — classified from
the error text (`includes(…)`) after `photo:startUpload` / upload /
`photo.create`. Ported in `lib/maps/streetview_errors.dart`.

#### Viewer internals

`assets/viewer/` bundles **two** WebView viewers: `viewer1.html`
(Photo Sphere Viewer 4, script tags) and `viewer.html` (PSV 5 "upgrade",
ESM import map) — both with autorotate + gyroscope plugins and a spatial
comment marker layer (`load-comments` / `add-comment` / `fly-to` /
long-press → `{yaw, pitch}` via `getIntersections`). Configuration:
`navbar: false`, `defaultZoomLvl: 0`, autorotate `3rpm` without
autostart, gyroscope `touchmove: true, absolutePosition: false`.

#### Remaining UX strings recovered

- Onboarding: `"Plant your feet and rotate in one spot."`,
  `"Stand 3-4 feet away from nearby objects or surfaces."`
- Photo details: `"Photo name"` (maxLength 200), `"Photo description"`,
  `"Photo name can't be empty"`
- Import: `"Imported Photo"`, `"Not a 360° Photo"`,
  `"Failed to import file"`, `/temp_import_` temp dir
- Analytics events (`Import_Button_Pressed`, `Capture_Button_Pressed`,
  `Save_Button_Tapped_On_PhotoNameScreen`, `StreetView_Upload_Button_Tapped`,
  `Play/Gyroscope/Menu/Close/Delete/Download/Google_Maps/Share/Post/Unlock_
  Button_Tapped_On_*_Viewer_Screen`, …) — the full button map of every
  screen.

#### Wave-3 additions (fresh jadx + hermes-dec pass)

- **Capture haptic** — the only app-side haptic call in the bundle:
  `HapticFeedback.trigger('impactLight', …)` fired the moment a dot flips
  to `CAPTURED` inside the capture worklet.
- **Capture constants** (constants module, exact values):
  `CAPTURE_STATUS = {NOT_CAPTURED: 0, HOLDING: 1, CAPTURED: 2, CAPTURING: 3}`
  (alphabetical values; the state-machine order differs),
  `PROCESS_STATUS = {INITIAL: 0, CAPTURE: 1, PROCESSING: 2, DONE: 3, FAILED: 4}`,
  `SENSOR_INTERVAL = 30`, `SENSOR_INTERVAL_LOW = 50`, `FILTER_ALPHA = 0.5`,
  `waitHoldTime = 100`, `deltaRotationMarkAngle = 20`.
- **HUD geometry** — `ratio = screenWidth / 375` (iPhone design width);
  `greenTarget = 177 × 255 · 0.87 · ratio`; `gap = 20·ratio`,
  `gapBottom = 60·ratio`, `arrowRadius = 80·ratio`; signature green
  `#49FF83` (target dots, pin layer, active buttons).
- **File naming** — `date2string` renders `YYYY_MM_DD_HH_mm_ss`
  (underscores) for photo dates; downloads are named
  `<makeRandomString(10)>.jpg`.
- **Manifest permissions** relevant to the core pipeline: `CAMERA`,
  `ACCESS_FINE/COARSE_LOCATION` (the geo pose), `VIBRATE` (the capture
  haptic), `HIGH_SAMPLING_RATE_SENSORS` (the orientation module);
  `RECORD_AUDIO` is react-native-vision-camera's video surface (the app
  itself captures stills only).

### Feature inventory (evidence strings)

- Watermarking & unlock economy: *"As a guest, you may only view your 360 Photos with watermarks… only registered users may unlock watermarks, and download images"*, *"Unlock Your 360 Photos!"*, *"You must use one Unlock for this previously captured 360 Photo."*
- Sharing: *"Check Out My Space in 360°"* (Facebook/X/Instagram/WhatsApp/TikTok hashtags), hosted viewer at `https://share.360photo.cam/viewer/`.
- **Google integration**: Street View publishing scope `https://www.googleapis.com/auth/streetviewpublish`; *"Adding to Google Maps is available only for 360° photos taken directly with this app."*; Google Maps search links.
- Community showcase: *"Be the first to share your 360° photos with the community!"*, *"Get inspired by amazing 360° photos from our community"*, content guidelines text.

### Backend API surface (`https://360app.dospace.tech`)

```
/api/v2/comments/                     /api/v2/user
/api/v2/common/awsDeleteUploadedImages  /api/v2/user/alert
/api/v2/common/awsGetPreSignedUrl       /api/v2/user/apple-login
/api/v2/common/awsGetPreSignedUrlWithAuth  /api/v2/user/check_email
/api/v2/common/awsPutPreSignedUrl       /api/v2/user/create-short-link
/api/v2/common/awsPutPreSignedUrlWithOctream  /api/v2/user/error-report
/api/v2/common/awsPutTextObject         /api/v2/user/expand-short-link
/api/v2/showcase/photo-url/             /api/v2/user/facebook-post
/api/v2/showcase/photo/                 /api/v2/user/generate-token
/api/v2/showcase/thumbnail-url/         /api/v2/user/get-price-date
                                        /api/v2/user/google-login
                                        /api/v2/user/new-password
                                        /api/v2/user/report-purchase-issue
                                        /api/v2/user/send-code
                                        /api/v2/user/send-feedback
                                        /api/v2/user/signin
                                        /api/v2/user/signup
                                        /api/v2/user/unlock-photo
                                        /api/v2/user/update-profile
                                        /api/v2/user/verify-code
                                        /api/v2/user/verify-subscriber-code
```

AWS S3 presigned uploads power photo storage; short links power sharing.

## What this recreation implements (core pipeline)

| Original feature | Recreation |
| --- | --- |
| Dot-target capture (33/30-dot sphere layout, hold-to-capture 3°/5°/s/400 ms) | ✅ semantics port of the `useCaptureWorklet` (`lib/capture/dots/`) |
| Native `OrientationAngle` pipeline (game-rotation-vector euler, ±25° yaw clamp, α=0.8 low-pass) | ✅ faithful Dart port feeding the dot director (`lib/capture/orientation/original_orientation_filter.dart`) |
| Capture modes (photosphere + horizontal / vertical / wide-angle / fisheye panoramas) | ✅ all five, incl. equidistant fisheye projection |
| Camera sweep with gyro guidance | ✅ quaternion HUD (green targets, hold ring, arrow, coverage ring) |
| First-run instructions ("Plant your feet…", "Stand 3-4 feet away…") | ✅ first-run overlay + help sheet |
| 4-step processing UX ("Stitching… Step X/4" → "Finishing…") | ✅ local composite → encode → thumbnail → store, same step counter |
| GPano XMP 360° metadata | ✅ written at stitch time, on import, checked before Street View upload |
| Skia offscreen-texture stitching | ✅ `Canvas.drawVertices` textured mesh onto an equirect canvas (same Skia engine that Flutter renders with) |
| Stitching pass after capture | ✅ finalize + JPEG encode (auto-finishes when all dots are captured) |
| Photo name + description (PhotoNameScreen) | ✅ detail-screen editor, 200-char name, same validation message |
| Import existing 360° photos with "Not a 360° Photo" validation | ✅ My 360s import button, GPano/2:1 validation, GPano stamping |
| My360s gallery | ✅ local file store + grid |
| 360° viewer (PSV + three.js) | ✅ same runtime & configuration (vendored, base64 bridge); Play/autorotate, gyroscope, share, save, delete |
| Street View error dialogs (8 classifications) | ✅ `lib/maps/streetview_errors.dart` + pre-flight check |
| Share | ✅ file share (no backend, so no hosted viewer link) |
| **Publish to Google Maps / Street View** | ✅ Street View Publish API v1 (see docs/GOOGLE-MAPS-UPLOAD.md) — `pose.latLngPair` + `captureTime {seconds}` request shapes verified against the original's decompiled publisher (Wave 3) |
| Geo pose captured with the photo (original's `geo_location`) | ✅ best-effort GPS fix at capture start, persisted, prefills the publish sheet (Wave 3) |
| `shareLink` from Google + "Open in Google Maps" | ✅ extracted, persisted, opened via url_launcher (Wave 3) |
| Capture haptic (`impactLight` on each captured dot) | ✅ `HapticFeedback.lightImpact()` gated on real dot transitions (Wave 3) |
| Watermark "Created in … by {author}" | ✅ author-name watermark setting |
| Cloud stitching / rendering pipeline | ❌ out of scope (offline recreation stitches locally; same 4-step UX) |
| Viewer comment pins / long-press coordinates | ❌ community backend feature (math documented above) |
| Auth / community / billing / push | ❌ out of scope (core pipeline) — endpoints documented above for a future backend; see [REVISION.md](REVISION.md) for the full gap matrix |

## Legal note

This is a **clean-room recreation**: architecture and behavior were learned by
inspection; no app code, assets or strings from the original are copied. The
original app is © its authors. Analyze only software you are authorized to
analyze; REA's own disclaimer applies to any reverse-engineering tooling.
