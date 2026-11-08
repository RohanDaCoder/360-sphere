# Publishing 360° photos to Google Maps

360Sphere can publish your photospheres to **Google Street View**, which
makes them eligible to appear on Google Maps — the same capability the
original app exposes ("Adding to Google Maps is available only for 360°
photos taken directly with this app").

## Prerequisites

- A Google account.
- A one-time OAuth setup (below) — the Street View Publish API requires
  user-consented OAuth; API keys are not accepted for publishing.
- Photos must be **equirectangular JPEG, 2:1 aspect ratio, at least 4K**
  (360Sphere's default 4096×2048 output qualifies).

## One-time OAuth setup (developer)

The app uses `google_sign_in` with the scope
`https://www.googleapis.com/auth/streetviewpublish`. To make the Google
Sign-In button work on Android you must provide a **Web OAuth client ID**:

1. Open [Google Cloud Console](https://console.cloud.google.com/) and create
   (or pick) a project.
2. Enable the **Street View Publish API** for the project.
3. Configure the **OAuth consent screen**:
   - User type: External.
   - Add the scope `.../auth/streetviewpublish` and `email`.
   - While unverified, add your tester accounts under **Test users**.
4. Create credentials → **OAuth client ID** → type **Web application**.
   (A Web client ID works for `google_sign_in` on Android; Android client
   IDs with SHA-1 fingerprints are for distribution builds.)
   For release builds also add an **Android** OAuth client with your
   signing SHA-1.
5. Put the Web client ID into the app — either:

   **a)** `android/app/src/main/res/values/strings.xml`:
   ```xml
   <resources>
       <string name="default_web_client_id">XXXX.apps.googleusercontent.com</string>
   </resources>
   ```
   (create the file/values folder if missing), or

   **b)** add `google-services.json` from Firebase and apply the
   `com.google.gms.google-services` Gradle plugin.

6. If you publish on Play Store with the `streetviewpublish` scope, Google
   requires OAuth **app verification** for production; during development,
   test-user mode is enough.

## The publish flow (what the app does)

`lib/maps/streetview_publish_service.dart` implements the official 3-step
sequence:

| Step | Call | Purpose |
| --- | --- | --- |
| 1 | `POST /v1/photo:startUpload` | obtain a short-lived upload URL |
| 2 | `PUT <uploadUrl>` (octet-stream) | upload the equirect JPEG bytes |
| 3 | `POST /v1/photo` | register the photo with `pose` (lat/lng/heading) |

The pose is auto-filled from the device location (`geolocator`) with a
manual heading slider. On success the photo id is stored with the sphere and
the detail screen shows a "Published to Google Street View" badge.

Processing can take from minutes to days before the photo becomes visible on
Maps. You can inspect your uploads at <https://streetview.google.com/collections>.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `sign_in_failed` at sign-in | `default_web_client_id` missing/incorrect — see setup step 5. |
| `403 … PERMISSION_DENIED` on startUpload | Scope not granted: the OAuth screen must include `streetviewpublish`, and your account must be a consent-screen test user (or the app verified). |
| `403 … streetviewpublish.apiNotActivated` | Enable the API in Cloud Console (step 2). |
| `400 … invalid photo` | Photo must be 2:1 equirectangular JPEG ≥ 4K — keep the default 4096 output resolution. |
| Photo never appears on Maps | Google reviews uploaded photos; check Street View collections for processing status. |
