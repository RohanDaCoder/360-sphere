# Third-party notices

This project vendors the following open-source runtimes in
`assets/viewer/js/` and `assets/fonts/`:

## three.js
- Files: `assets/viewer/js/three.min.js`
- License: MIT — https://github.com/mrdoob/three.js/blob/dev/LICENSE
- Copyright © 2010-2024 three.js authors.

## Photo Sphere Viewer (core + autorotate + gyroscope plugins)
- Files: `assets/viewer/js/photo-sphere-viewer.min.js`,
  `psv-autorotate-plugin.min.js`, `psv-gyroscope-plugin.min.js`, `style.css`
- License: MIT — https://github.com/mistic100/Photo-Sphere-Viewer/blob/main/LICENSE.md
- Copyright © 2014-2024 Damien "Mistic" Sorel.

## Fonts
- Files: `assets/fonts/Montserrat-*.ttf` — Montserrat, SIL Open Font License 1.1,
  Copyright © 2011-2024 The Montserrat Project Authors (Julieta Ula).
- Files: `assets/fonts/Inter-Regular.ttf` — Inter, SIL Open Font License 1.1,
  Copyright © 2016-2024 The Inter Project Authors (Rasmus Andersson).

The Photo Sphere Viewer integration page (`assets/viewer/viewer.html`) is a
clean-room page written for this project, calling the public PSV 4 API.

Dart/Flutter packages (BSD-style licenses, resolved by `flutter pub get`)
are listed in `pubspec.yaml` / `pubspec.lock`.
