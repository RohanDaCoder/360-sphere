# 360Sphere

[![Lint](https://github.com/RohanDaCoder/360-sphere/actions/workflows/lint.yml/badge.svg)](https://github.com/RohanDaCoder/360-sphere/actions/workflows/lint.yml)
[![Test](https://github.com/RohanDaCoder/360-sphere/actions/workflows/test.yml/badge.svg)](https://github.com/RohanDaCoder/360-sphere/actions/workflows/test.yml)
[![Release APK](https://github.com/RohanDaCoder/360-sphere/actions/workflows/apk.yml/badge.svg)](https://github.com/RohanDaCoder/360-sphere/actions/workflows/apk.yml)

Capture, stitch and share **360° photospheres** — a clean-room Flutter
recreation of the *360 Photo Cam* app architecture, including publishing to
**Google Maps / Street View**.

Sweep your phone around, watch the gyro-guided coverage ring fill up, and the
Skia-based stitching engine assembles your frames into a 4096×2048
equirectangular photo you can view immersively, share, and publish.

## Features

- 🎯 **Dot-target guided capture** — the original app's capture mechanic,
  ported from its decompiled `useCaptureWorklet`: a 33-dot sphere layout
  (13 equator / 9 top / 9 bottom / ceiling / floor; 30 for wide lenses),
  hold-to-capture (aim within 3°, < 5°/s, 400 ms → auto shutter),
  pitch-weighted target selection, sticky targets, polar-last ordering and
  an optional floor dot.
- 📷 **Five capture modes** — photosphere + horizontal / vertical /
  wide-angle / fisheye panoramas, matching the original's mode set; the
  fisheye mode warps through an equidistant lens model.
- 🧵 **Skia mesh-warp stitching** — camera frames are warped onto the
  equirectangular projection through a per-vertex feathered textured mesh
  (`Canvas.drawVertices`), the same offscreen-texture technique the original
  React Native app implements with Shopify Skia worklets.
- 🖼️ **Immersive viewer** — Photo Sphere Viewer + three.js (vendored), with
  Play (autorotate), gyroscope, share, save and delete actions.
- 🗺️ **Publish to Google Maps** — full Street View Publish API flow
  (sign-in, upload, geo-pose). See [docs/GOOGLE-MAPS-UPLOAD.md](docs/GOOGLE-MAPS-UPLOAD.md).
- 🔗 **Share & save** — share the equirect image anywhere; save to the
  gallery.
- ✍️ **Author watermark** — "Created in 360Sphere by {author}", following
  the original's watermark pattern.
- ⚙️ **Calibration settings** — output resolution, camera FOV (40–180°),
  floor-dot capture, watermark author, compass assist, frame-rotation fix.

## Getting started

```bash
flutter pub get
flutter run          # on an Android device (camera + sensors required)
flutter test         # 53 unit tests: dots, hold-to-capture, fusion, projection, mesh, EXIF
flutter build apk    # release APK
```

> Camera, gyroscope and (for publishing) location permissions are requested
> at runtime. A physical device is required — emulators lack real sensors.

## CI & releases

Three GitHub Actions workflows run on every commit:

| Workflow | What it does |
| --- | --- |
| **Lint** | `dart format` check + `flutter analyze --fatal-infos` |
| **Test** | `flutter test --coverage`, lcov report uploaded as artifact |
| **Release APK** | `flutter build apk --release`, APK uploaded as a run artifact |

The release APK is built on **every commit** and attached to the workflow run
as a downloadable artifact (`sphere360-v<version>-<sha>.apk`).

**Publishing a release:** push a version tag and the APK is attached to a
GitHub Release automatically:

```bash
git tag v0.1.0
git push origin v0.1.0
```

**Signing:** without configuration, release builds are signed with debug keys.
To sign with your own keystore, add these repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 release.keystore` of your keystore |
| `ANDROID_STORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |

Create a keystore with:

```bash
keytool -genkey -v -keystore release.keystore -alias sphere360 \
  -keyalg RSA -keysize 2048 -validity 10000
```

## Project structure

```
lib/
  main.dart                     app bootstrap (providers, theme)
  app_shell.dart                bottom navigation
  core/                         theme, models, settings, repository
  capture/
    orientation/                quaternion math + sensor fusion
    dots/                       dot layouts + hold-to-capture director
                                (port of the original capture worklet)
    stitching/                  equirect projection (pinhole + fisheye),
                                mesh warp, EXIF, codec
    widgets/                    capture HUD (green targets, hold ring,
                                arrow, outlines, coverage ring)
    camera_screen.dart          capture UI + session orchestration
  gallery/                      My360s grid + sphere detail (actions)
  viewer/                       PSV WebView bridge + fullscreen viewer
  maps/                         Street View publish service + Google auth
  share/                        share + save-to-gallery
  settings/                     preferences screen
assets/viewer/                  clean-room PSV page + vendored runtime
docs/
  REA-ANALYSIS.md               reverse-engineering findings (evidence-based)
  REVISION.md                   original-vs-recreation gap matrix
  ARCHITECTURE.md               original vs recreation, stitching math
  GOOGLE-MAPS-UPLOAD.md         Street View publishing + OAuth setup
```

## Documentation

- **[REA-ANALYSIS.md](docs/REA-ANALYSIS.md)** — what the original APK is made
  of (React Native/Hermes/vision-camera/Skia stack, screens, API surface,
  monetization), with evidence.
- **[REVISION.md](docs/REVISION.md)** — feature-by-feature gap matrix between
  the original and this recreation, with port/skip decisions and evidence.
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how the stitching engine
  works: quaternion fusion, pinhole→equirect mesh warping, fisheye lens
  model, seam handling.
- **[GOOGLE-MAPS-UPLOAD.md](docs/GOOGLE-MAPS-UPLOAD.md)** — one-time OAuth
  setup for Street View publishing.

## License & attribution

App code: MIT. Vendored runtimes and fonts are covered by
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This project is an educational clean-room recreation. It contains no code,
assets or text from the original app. Only analyze and publish content you
own or are authorized to use.
