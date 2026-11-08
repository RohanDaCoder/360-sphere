# 360Sphere

Capture, stitch and share **360° photospheres** — a clean-room Flutter
recreation of the *360 Photo Cam* app architecture, including publishing to
**Google Maps / Street View**.

Sweep your phone around, watch the gyro-guided coverage ring fill up, and the
Skia-based stitching engine assembles your frames into a 4096×2048
equirectangular photo you can view immersively, share, and publish.

## Features

- 📷 **Gyro-guided capture** — live coverage ring, next-gap arrow, auto-sweep
  or manual shutter; photosphere (full sphere) and horizontal panorama modes.
- 🧵 **Skia mesh-warp stitching** — camera frames are warped onto the
  equirectangular projection through a per-vertex feathered textured mesh
  (`Canvas.drawVertices`), the same offscreen-texture technique the original
  React Native app implements with Shopify Skia worklets.
- 🖼️ **Immersive viewer** — Photo Sphere Viewer + three.js (vendored), with
  autorotate and gyroscope support.
- 🗺️ **Publish to Google Maps** — full Street View Publish API flow
  (sign-in, upload, geo-pose). See [docs/GOOGLE-MAPS-UPLOAD.md](docs/GOOGLE-MAPS-UPLOAD.md).
- 🔗 **Share & save** — share the equirect image anywhere; save to the
  gallery.
- ⚙️ **Calibration settings** — output resolution, camera FOV, watermark,
  compass assist, frame-rotation fix.

## Getting started

```bash
flutter pub get
flutter run          # on an Android device (camera + sensors required)
flutter test         # 34 unit tests: fusion, projection, mesh, EXIF
flutter build apk    # release APK
```

> Camera, gyroscope and (for publishing) location permissions are requested
> at runtime. A physical device is required — emulators lack real sensors.

## Project structure

```
lib/
  main.dart                     app bootstrap (providers, theme)
  app_shell.dart                bottom navigation
  core/                         theme, models, settings, repository
  capture/
    orientation/                quaternion math + sensor fusion
    stitching/                  equirect projection, mesh warp, EXIF, codec
    widgets/                    capture HUD (coverage ring, reticle, arrows)
    camera_screen.dart          capture UI + session orchestration
  gallery/                      My360s grid + sphere detail (actions)
  viewer/                       PSV WebView bridge + fullscreen viewer
  maps/                         Street View publish service + Google auth
  share/                        share + save-to-gallery
  settings/                     preferences screen
assets/viewer/                  clean-room PSV page + vendored runtime
docs/
  REA-ANALYSIS.md               reverse-engineering findings (evidence-based)
  ARCHITECTURE.md               original vs recreation, stitching math
  GOOGLE-MAPS-UPLOAD.md         Street View publishing + OAuth setup
```

## Documentation

- **[REA-ANALYSIS.md](docs/REA-ANALYSIS.md)** — what the original APK is made
  of (React Native/Hermes/vision-camera/Skia stack, screens, API surface,
  monetization), with evidence.
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how the stitching engine
  works: quaternion fusion, pinhole→equirect mesh warping, seam handling.
- **[GOOGLE-MAPS-UPLOAD.md](docs/GOOGLE-MAPS-UPLOAD.md)** — one-time OAuth
  setup for Street View publishing.

## License & attribution

App code: MIT. Vendored runtimes and fonts are covered by
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This project is an educational clean-room recreation. It contains no code,
assets or text from the original app. Only analyze and publish content you
own or are authorized to use.
