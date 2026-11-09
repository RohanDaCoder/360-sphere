import 'dart:math' as math;

import 'quaternion.dart';

/// Dart port of the original app's native `OrientationAngle` module
/// (`com.reactnativeorientationangle.OrientationAngleModule`, recovered by
/// decompiling the APK — see docs/REVISION.md).
///
/// The module listens to the device's rotation-vector sensor, converts the
/// quaternion to camera-style euler angles, clamps yaw jumps and low-pass
/// filters the result before emitting `pitch` / `roll` / `yaw` events that
/// drive the capture UI. This class reproduces that math exactly:
///
/// * **pitch** = `atan2(2·(w·x + y·z), 1 − 2·(x² + y²))`, mapped from
///   (−180, −90) up into (180, 270) when it dips below −90° (the module's
///   range fix), then shifted by **−90°** so an upright phone reads 0° and
///   looking up reads positive (matches the dot layout rows at ±45°/±90°);
///   the output stays in (−180°, 180°];
/// * **roll** = `asin(2·(w·y − x·z))`;
/// * **yaw** = `−atan2(2·(x·y + w·z), 1 − 2·(y² + z²))`, so yaw increases
///   while turning to the right;
/// * each raw yaw reading is clamped to **±25°** of the previous reading
///   (the module's `MAX_RAW_YAW_DELTA`, which immunizes the UI against
///   sensor glitches and magnetic re-referencing jumps);
/// * all three angles are smoothed with the module's low-pass filter
///   (α = 0.8: `prev += 0.8 · (value − prev)`), yaw differences taken on
///   the wrapped circle.
///
/// The input quaternion maps device → world (the same convention as the
/// Android rotation vector and [OrientationTracker]).
class OriginalOrientationFilter {
  OriginalOrientationFilter({
    this.maxRawYawDeltaDeg = 25,
    this.alpha = 0.8,
  });

  /// `MAX_RAW_YAW_DELTA` — maximum yaw change accepted from one reading.
  final double maxRawYawDeltaDeg;

  /// Low-pass filter coefficient (the module's `alpha`, default 0.8).
  final double alpha;

  double _prevPitch = -1000;
  double _prevRoll = -1000;
  double _prevYaw = -1000;
  double _prevRawYaw = -1000;

  /// Latest filtered angles, degrees. Pitch 0 = phone upright (camera
  /// horizontal), positive = tilted up; yaw 0–360, increasing to the right;
  /// roll 0 = screen upright.
  double pitchDeg = 0;
  double rollDeg = 0;
  double yawDeg = 0;

  /// Whether at least one reading has been processed.
  bool get initialized => _prevYaw != -1000;

  /// Feed one orientation sample and update [pitchDeg] / [rollDeg] /
  /// [yawDeg]. Returns the filtered result.
  (double pitch, double roll, double yaw) update(Quaternion q) {
    final w = q.w, x = q.x, y = q.y, z = q.z;

    // pitch: X-axis rotation, camera-pose convention (see class docs).
    var p = math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y)) *
        180 /
        math.pi;
    // The module's range fix: atan2 values below −90° (i.e. in
    // (−180, −90)) are lifted by +360° so the post-shift pitch stays
    // inside (−180°, 180°] instead of wrapping to −270…−180.
    if (p < 0 && p.abs() > 90) p += 360;
    final pitchOut = p - 90;

    // roll: Y-axis rotation via asin.
    final rollOut = math.asin(
          (2 * (w * y - x * z)).clamp(-1.0, 1.0),
        ) *
        180 /
        math.pi;

    // yaw: negated Z-axis rotation.
    final yawRaw = -math.atan2(2 * (x * y + w * z), 1 - 2 * (y * y + z * z)) *
        180 /
        math.pi;

    if (!initialized) {
      _prevPitch = pitchOut;
      _prevRoll = rollOut;
      _prevYaw = _normalize(yawRaw);
      _prevRawYaw = _prevYaw;
      pitchDeg = _prevPitch;
      rollDeg = _prevRoll;
      yawDeg = _prevYaw;
      return (pitchDeg, rollDeg, yawDeg);
    }

    // Clamp the raw yaw delta (glitch immunity) before filtering.
    var d = _normalize(yawRaw - _prevRawYaw);
    if (d > maxRawYawDeltaDeg) {
      d = maxRawYawDeltaDeg;
    } else if (d < -maxRawYawDeltaDeg) {
      d = -maxRawYawDeltaDeg;
    }
    final yawClamped = _normalize(_prevRawYaw + d);
    _prevRawYaw = yawClamped;

    // Low-pass filter, yaw on the wrapped circle.
    _prevPitch += (pitchOut - _prevPitch) * alpha;
    _prevRoll += (rollOut - _prevRoll) * alpha;
    _prevYaw += _normalize(yawClamped - _prevYaw) * alpha;
    _prevYaw = _normalize(_prevYaw);

    pitchDeg = _prevPitch;
    rollDeg = _prevRoll;
    yawDeg = _prevYaw;
    return (pitchDeg, rollDeg, yawDeg);
  }

  /// Reset to the module's fresh-start state (its `stopUpdates` clears the
  /// previous samples the same way).
  void reset() {
    _prevPitch = -1000;
    _prevRoll = -1000;
    _prevYaw = -1000;
    _prevRawYaw = -1000;
    pitchDeg = 0;
    rollDeg = 0;
    yawDeg = 0;
  }

  static double _normalize(double deg) {
    // The module's normalizeAngle wraps into [−180, 180] (values > 180°
    // fold back, values < −180° fold forward) — verified against the
    // decompiled `OrientationAngleModule.normalizeAngle`. This matters at
    // the seam: a turn from +170° to −170° is a −20° move, not +340°.
    var d = deg;
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return d;
  }
}

/// Degree-space angular difference in (−180, 180], matching the module's
/// `normalizeAngle`-based comparisons.
double angleDeltaDeg(double a, double b) {
  var d = b - a;
  while (d > 180) {
    d -= 360;
  }
  while (d < -180) {
    d += 360;
  }
  return d;
}
