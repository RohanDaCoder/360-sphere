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
3. **hermes-dec** — decompilation of the 5.4 MB `assets/index.android.bundle` (Hermes bytecode, HBC v96) into 937,513 lines of readable pseudocode plus the full string table (20,470 unique strings).

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

`RootNavigator` → bottom tabs / stack: **Camera, Capture, Community, My360s, Premium, Settings, Stitching, Subscription**.

### Capture modes

`panorama-wide-angle`, `panorama-vertical`, `panorama-horizontal`, `panorama-fisheye`, plus the flagship **photosphere** (gyroscope-guided) — icon names recovered from the bundle strings.

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
| Camera sweep with gyro guidance | ✅ still-shot sweep + quaternion HUD (coverage ring, next-gap arrow) |
| Skia offscreen-texture stitching | ✅ `Canvas.drawVertices` textured mesh onto an equirect canvas (same Skia engine that Flutter renders with) |
| Stitching pass after capture | ✅ finalize + JPEG encode |
| My360s gallery | ✅ local file store + grid |
| 360° viewer (PSV + three.js) | ✅ same runtime, vendored, streamed via base64 bridge |
| Share | ✅ file share (no backend, so no hosted viewer link) |
| **Publish to Google Maps / Street View** | ✅ Street View Publish API v1 (see docs/GOOGLE-MAPS-UPLOAD.md) |
| Watermark | ✅ optional signature stamp |
| Auth / community / billing / push | ❌ out of scope (core pipeline) — endpoints documented above for a future backend |

## Legal note

This is a **clean-room recreation**: architecture and behavior were learned by
inspection; no app code, assets or strings from the original are copied. The
original app is © its authors. Analyze only software you are authorized to
analyze; REA's own disclaimer applies to any reverse-engineering tooling.
